package com.example.app.sync;

import static com.example.app.sync.DictionaryCatalog.identifier;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.app.sync.DictionaryCatalog.Column;
import com.example.app.sync.DictionaryCatalog.Definition;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Service
public class DictionaryApplyService {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public DictionaryApplyService(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    // Все шаги применения выполняются в одной транзакции, без HTTP-запросов.
    @Transactional
    public void apply(
        UUID runId,
        Definition dictionary,
        String version,
        long expectedRows,
        boolean allowEmpty
    ) {
        validateAndLockRun(runId, dictionary.name());

        String targetTable = "data." + identifier(dictionary.name());
        String columns = targetColumns(dictionary);
        String keyCondition = keyCondition(dictionary);

        prepareIncomingTable(dictionary.name(), targetTable);
        recordCurrentSnapshot(runId, dictionary.name(), targetTable);
        long receivedRows = loadIncomingRows(runId, dictionary, columns);
        validateRowCount(receivedRows, expectedRows, allowEmpty);

        long matchedRows = countMatchingRows(targetTable, keyCondition);
        upsertTargetRows(dictionary, targetTable, columns);
        int deletedRows = markMissingRowsDeleted(targetTable, keyCondition);

        replaceStaging(dictionary, columns);
        recordNewSnapshot(runId, targetTable);
        saveLoadedVersion(dictionary, version);
        completeRun(runId, receivedRows - matchedRows, matchedRows, deletedRows);
    }

    private void validateAndLockRun(UUID runId, String dictionaryName) {
        List<Map<String, Object>> runs = jdbc.queryForList(
            """
            SELECT status, entity_name
            FROM data.dsa_load_batch
            WHERE run_id = ?
            FOR UPDATE
            """,
            runId
        );

        if (runs.size() != 1
            || !"running".equals(runs.getFirst().get("status"))
            || !dictionaryName.equals(runs.getFirst().get("entity_name"))) {
            throw new IllegalStateException(
                "Загрузка уже отменена или не соответствует справочнику"
            );
        }
    }

    private void prepareIncomingTable(String dictionaryName, String targetTable) {
        jdbc.execute("""
            DO $$
            BEGIN
                PERFORM pg_advisory_xact_lock(
                    hashtextextended('dsa_data_load.%s', 0)
                );
            END $$
            """.formatted(dictionaryName));

        jdbc.execute("LOCK TABLE " + targetTable + " IN SHARE ROW EXCLUSIVE MODE");
        jdbc.execute(
            "CREATE TEMP TABLE nsi_incoming (LIKE " + targetTable
                + " INCLUDING ALL) ON COMMIT DROP"
        );
    }

    private void recordCurrentSnapshot(UUID runId, String name, String targetTable) {
        jdbc.update("""
            UPDATE data.dsa_load_batch
            SET current_version = (SELECT version FROM data.dsa_loaded_version WHERE entity_name = ?),
                rows_current = (SELECT count(*) FROM %s),
                rows_current_deleted = (SELECT count(*) FROM %s WHERE is_deleted = 'Y')
            WHERE run_id = ?
            """.formatted(targetTable, targetTable), name, runId);
    }

    private void recordNewSnapshot(UUID runId, String targetTable) {
        jdbc.update("""
            UPDATE data.dsa_load_batch
            SET rows_new = (SELECT count(*) FROM %s),
                rows_new_deleted = (SELECT count(*) FROM %s WHERE is_deleted = 'Y'),
                rows_rejected = 0
            WHERE run_id = ?
            """.formatted(targetTable, targetTable), runId);
    }

    private long loadIncomingRows(UUID runId, Definition dictionary, String columns) {
        int pageCount = jdbc.queryForObject(
            "SELECT count(*) FROM data.nsi_sync_page WHERE run_id = ? AND kind = 'data'",
            Integer.class,
            runId
        );

        String placeholders = String.join(",", Collections.nCopies(dictionary.columns().size(), "?"));
        String insertSql = "INSERT INTO nsi_incoming (" + columns + ") VALUES (" + placeholders + ")";
        long receivedRows = 0;

        for (int pageNumber = 0; pageNumber < pageCount; pageNumber++) {
            JsonNode page = readDataPage(runId, pageNumber);
            List<Object[]> rows = convertRows(dictionary, page, pageNumber);

            jdbc.batchUpdate(insertSql, rows);
            receivedRows += rows.size();
        }

        return receivedRows;
    }

    private JsonNode readDataPage(UUID runId, int pageNumber) {
        String payload = jdbc.queryForObject(
            """
            SELECT payload::text
            FROM data.nsi_sync_page
            WHERE run_id = ? AND kind = 'data' AND page_number = ?
            """,
            String.class,
            runId,
            pageNumber
        );

        return mapper.readTree(payload).path("list");
    }

    private List<Object[]> convertRows(Definition dictionary, JsonNode page, int pageNumber) {
        List<Object[]> rows = new ArrayList<>();

        for (JsonNode rawRow : page) {
            Map<String, JsonNode> fields = SourceValues.fields(rawRow);
            Object[] values = new Object[dictionary.columns().size()];

            for (int columnIndex = 0; columnIndex < values.length; columnIndex++) {
                Column column = dictionary.columns().get(columnIndex);

                try {
                    values[columnIndex] = SourceValues.convert(fields.get(column.source()), column.type());
                } catch (RuntimeException exception) {
                    throw new IllegalArgumentException(
                        "Страница " + pageNumber + ", строка " + (rows.size() + 1)
                            + ", поле " + column.source() + ": неверный тип/формат"
                    );
                }
            }

            rows.add(values);
        }

        return rows;
    }

    private void validateRowCount(long receivedRows, long expectedRows, boolean allowEmpty) {
        if (receivedRows != expectedRows || (receivedRows == 0 && !allowEmpty)) {
            throw new IllegalArgumentException("Неполный или запрещённый пустой снимок");
        }
    }

    private long countMatchingRows(String targetTable, String keyCondition) {
        return jdbc.queryForObject(
            "SELECT count(*) FROM " + targetTable + " t JOIN nsi_incoming s ON " + keyCondition,
            Long.class
        );
    }

    private void upsertTargetRows(Definition dictionary, String targetTable, String columns) {
        String keys = dictionary.keys().stream()
            .map(DictionaryCatalog::identifier)
            .collect(Collectors.joining(","));

        String updates = dictionary.columns().stream()
            .filter(column -> !dictionary.keys().contains(column.target()))
            .map(column -> identifier(column.target()) + " = excluded." + identifier(column.target()))
            .collect(Collectors.joining(", "));

        jdbc.update("""
            INSERT INTO %s (%s)
            SELECT %s FROM nsi_incoming WHERE true
            ON CONFLICT (%s) DO UPDATE SET %s, is_deleted = 'N'
            """.formatted(targetTable, columns, columns, keys, updates));
    }

    private int markMissingRowsDeleted(String targetTable, String keyCondition) {
        return jdbc.update("""
            UPDATE %s t
            SET is_deleted = 'Y'
            WHERE t.is_deleted = 'N'
              AND NOT EXISTS (SELECT 1 FROM nsi_incoming s WHERE %s)
            """.formatted(targetTable, keyCondition));
    }

    private void replaceStaging(Definition dictionary, String columns) {
        String stagingTable = "data." + identifier("dsa_raw_" + dictionary.name());
        String stagingColumns = dictionary.columns().stream()
            .map(column -> identifier(column.staging()))
            .collect(Collectors.joining(","));

        jdbc.execute("LOCK TABLE " + stagingTable + " IN SHARE ROW EXCLUSIVE MODE");
        jdbc.update("DELETE FROM " + stagingTable);
        jdbc.update(
            "INSERT INTO " + stagingTable + " (" + stagingColumns + ") SELECT "
                + columns + " FROM nsi_incoming"
        );

        if (dictionary.keys().equals(List.of("id"))) {
            jdbc.update("UPDATE " + stagingTable + " SET new_id = id");
        } else {
            String keyPairs = dictionary.keys().stream()
                .map(key -> "'" + key + "'," + identifier(key))
                .collect(Collectors.joining(","));

            jdbc.update(
                "UPDATE " + stagingTable + " SET new_key = jsonb_build_object(" + keyPairs + ")"
            );
        }
    }

    private void saveLoadedVersion(Definition dictionary, String version) {
        jdbc.update(
            """
            INSERT INTO data.dsa_loaded_version (
                entity_name, version, data_source, data_source_url, load_date
            )
            VALUES (?, ?, 'minzdrav', ?, now())
            ON CONFLICT (entity_name) DO UPDATE SET
                version = excluded.version,
                data_source = excluded.data_source,
                data_source_url = excluded.data_source_url,
                load_date = now()
            """,
            dictionary.name(),
            version,
            "https://nsi.rosminzdrav.ru/dictionaries/" + dictionary.oid()
        );
    }

    private void completeRun(UUID runId, long insertedRows, long updatedRows, long deletedRows) {
        jdbc.update(
            """
            UPDATE data.dsa_load_batch
            SET status = 'success', finished_at = now(),
                rows_inserted = ?, rows_updated = ?, rows_deleted = ?
            WHERE run_id = ? AND status = 'running'
            """,
            insertedRows,
            updatedRows,
            deletedRows,
            runId
        );
    }

    private String targetColumns(Definition dictionary) {
        return dictionary.columns().stream()
            .map(column -> identifier(column.target()))
            .collect(Collectors.joining(","));
    }

    private String keyCondition(Definition dictionary) {
        return dictionary.keys().stream()
            .map(key -> "t." + identifier(key) + " = s." + identifier(key))
            .collect(Collectors.joining(" AND "));
    }
}

