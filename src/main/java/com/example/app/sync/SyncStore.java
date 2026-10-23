package com.example.app.sync;

import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Repository
public class SyncStore {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final TransactionTemplate tx;
    public SyncStore(JdbcTemplate jdbc, ObjectMapper mapper, PlatformTransactionManager tm) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        tx = new TransactionTemplate(tm);
    }
    public UUID create(DictionaryCatalog.Definition d, SyncService.Request request) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
            INSERT INTO data.dsa_load_batch (
                run_id, entity_name, oid, requested_version, user_id,
                force_reload, allow_empty, status, data_source, data_source_url,
                dsa_table_name, data_table_name, load_type, loaded_by, rows_extracted
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, 'queued', 'minzdrav', ?, ?, ?, 'full', ?, 0)
            """, id, d.name(), d.oid(), request.version(), request.userId(),
            request.force(), request.allowEmpty(), "https://nsi.rosminzdrav.ru/dictionaries/" + d.oid(),
            "dsa_raw_" + d.name(), d.name(), String.valueOf(request.userId()));
        return id;
    }
    public boolean start(UUID id) {
        return jdbc.update("UPDATE data.dsa_load_batch SET status='running',started_at=now() WHERE run_id=? AND status='queued'", id) == 1;
    }
    public Map<String,Object> run(UUID id) {
        var rows = jdbc.queryForList("""
            SELECT run_id AS id,id AS batch_id,entity_name,oid,requested_version,new_version AS source_version,user_id,status,created_at,started_at,
                   finished_at,rows_extracted::bigint AS rows_received,rows_inserted::bigint AS rows_inserted,rows_updated::bigint AS rows_updated,rows_deleted::bigint AS rows_deleted,error_message
            FROM data.dsa_load_batch WHERE run_id=?
            """, id);
        if (rows.isEmpty()) {
            throw new NoSuchElementException("Загрузка не найдена");
        }
        return rows.getFirst();
    }
    public List<Map<String,Object>> history(String name, int limit, int offset) {
        return jdbc.queryForList("""
            SELECT run_id AS id,id AS batch_id,entity_name,new_version AS source_version,status,created_at,finished_at,rows_extracted::bigint AS rows_received,error_message
            FROM data.dsa_load_batch WHERE entity_name=? ORDER BY created_at DESC,run_id LIMIT ? OFFSET ?
            """, name, limit, offset);
    }
    public String loadedVersion(String name) {
        var versions = jdbc.queryForList("SELECT version FROM data.dsa_loaded_version WHERE entity_name=?", String.class, name);
        return versions.isEmpty() ? null : versions.getFirst();
    }
    public void passport(UUID id, String name, String version, JsonNode payload) {
        tx.executeWithoutResult(s -> {
            jdbc.update("UPDATE data.dsa_load_batch SET new_version=?,passport=?::jsonb WHERE run_id=?", version, payload.toString(), id);
            savePassport(name,version,payload);
        });
    }
    public boolean hasPassport(String name, String version) {
        return Boolean.TRUE.equals(jdbc.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM data.nsi_dictionary_passport WHERE entity_name=? AND version=?)",
            Boolean.class,name,version));
    }
    public void savePassport(String name, String version, JsonNode payload) {
        jdbc.update("""
                INSERT INTO data.nsi_dictionary_passport(entity_name,version,payload) VALUES (?,?,?::jsonb)
                ON CONFLICT(entity_name,version) DO UPDATE SET payload=excluded.payload,fetched_at=now()
                """, name, version, payload.toString());
    }
    public void page(UUID id, String kind, int number, JsonNode payload) {
        tx.executeWithoutResult(s -> {
            jdbc.update("INSERT INTO data.nsi_sync_page VALUES (?,?,?,?::jsonb)", id, kind, number, payload.toString());
            if (kind.equals("data")) jdbc.update(
                "UPDATE data.dsa_load_batch SET rows_extracted=rows_extracted+? WHERE run_id=?", payload.path("list").size(), id);
        });
    }
    public void versions(String name, JsonNode list) {
        tx.executeWithoutResult(s -> {
            for (var version : list) {
                var v = version.path("version").asText("");
                if (v.isBlank()) {
                    throw new IllegalArgumentException("Версия без номера");
                }
                jdbc.update("""
                    INSERT INTO data.nsi_dictionary_version(entity_name,version,payload) VALUES (?,?,?::jsonb)
                    ON CONFLICT(entity_name,version) DO UPDATE SET payload=excluded.payload,fetched_at=now()
                    """, name, v, version.toString());
            }
        });
    }
    public void finish(UUID id, String status, String message) {
        jdbc.update("""
            UPDATE data.dsa_load_batch SET status=?,error_message=?,finished_at=now()
            WHERE run_id=? AND status IN ('queued','running')
            """, status, message, id);
    }
    public JsonNode page(UUID id, String kind, int number) {
        var rows = jdbc.queryForList(
            "SELECT payload::text FROM data.nsi_sync_page WHERE run_id=? AND kind=? AND page_number=?",
            String.class, id, kind, number);
        if (rows.isEmpty()) {
            throw new NoSuchElementException("Страница не найдена");
        }
        return mapper.readTree(rows.getFirst());
    }
    public JsonNode passport(String name, String version) {
        var rows = jdbc.queryForList(
            "SELECT payload::text FROM data.nsi_dictionary_passport WHERE entity_name=? AND version=?",
            String.class, name, version);
        if (rows.isEmpty()) {
            throw new NoSuchElementException("Паспорт ещё не загружен");
        }
        return mapper.readTree(rows.getFirst());
    }
    public List<JsonNode> versions(String name, int limit, int offset) {
        return jdbc.queryForList("""
            SELECT payload::text FROM data.nsi_dictionary_version WHERE entity_name=?
            ORDER BY version LIMIT ? OFFSET ?
            """, String.class, name, limit, offset).stream().map(mapper::readTree).toList();
    }
    public List<Map<String,Object>> rows(DictionaryCatalog.Definition d, int limit, int offset, boolean deleted) {
        String keys = d.keys().stream().map(DictionaryCatalog::identifier).collect(java.util.stream.Collectors.joining(","));
        return jdbc.queryForList("SELECT * FROM data." + DictionaryCatalog.identifier(d.name())
            + (deleted ? "" : " WHERE is_deleted='N'") + " ORDER BY " + keys + " LIMIT ? OFFSET ?", limit, offset);
    }
}



