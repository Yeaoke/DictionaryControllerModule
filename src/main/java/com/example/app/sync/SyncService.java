package com.example.app.sync;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import javax.sql.DataSource;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;

import jakarta.annotation.PreDestroy;
import tools.jackson.databind.JsonNode;

@Service
public class SyncService {

    private static final int QUEUE_CAPACITY = 128;
    private static final int MAX_PAGE_SIZE = 1000;
    private static final int MAX_VERSION_LENGTH = 100;
    private static final int MAX_ERROR_LENGTH = 1000;

    public record Request(
        Long userId,
        String version,
        Boolean force,
        Boolean allowEmpty
    ) {
        public Request {
            force = Boolean.TRUE.equals(force);
            allowEmpty = Boolean.TRUE.equals(allowEmpty);

            if (userId == null) {
                throw new IllegalArgumentException("userId обязателен");
            }

            if (version != null && (version.isBlank() || version.length() > MAX_VERSION_LENGTH)) {
                throw new IllegalArgumentException(
                    "version должна содержать от 1 до 100 символов"
                );
            }
        }
    }

    private final DictionaryCatalog catalog;
    private final SyncStore store;
    private final NsiSourceClient source;
    private final DictionaryApplyService applyService;
    private final DataSource dataSource;
    private final int pageSize;
    private final int maxPages;

    private final ThreadPoolExecutor executor = new ThreadPoolExecutor(
        1,
        1,
        0,
        TimeUnit.SECONDS,
        new ArrayBlockingQueue<>(QUEUE_CAPACITY),
        task -> new Thread(task, "nsi-sync"),
        new ThreadPoolExecutor.AbortPolicy()
    );

    public SyncService(
        DictionaryCatalog catalog,
        SyncStore store,
        NsiSourceClient source,
        DictionaryApplyService applyService,
        DataSource dataSource,
        @Value("${nsi.minzdrav.page-size:500}") int pageSize,
        @Value("${nsi.minzdrav.max-pages:100000}") int maxPages
    ) {
        if (pageSize < 1 || pageSize > MAX_PAGE_SIZE || maxPages < 1) {
            throw new IllegalArgumentException("Invalid pagination config");
        }

        this.catalog = catalog;
        this.store = store;
        this.source = source;
        this.applyService = applyService;
        this.dataSource = dataSource;
        this.pageSize = pageSize;
        this.maxPages = maxPages;
    }

    public UUID submit(String name, Request request) {
        DictionaryCatalog.Definition dictionary = catalog.get(name);
        UUID runId = store.create(dictionary, request);

        try {
            executor.execute(() -> execute(runId, dictionary, request));
        } catch (RejectedExecutionException exception) {
            store.finish(
                runId,
                "failed",
                "Очередь загрузки заполнена или приложение останавливается"
            );
            throw exception;
        }

        return runId;
    }

    public List<Map<String, Object>> submitAll(Request request) {
        if (request.version() != null) {
            throw new IllegalArgumentException(
                "Общая версия для разных справочников не поддерживается"
            );
        }

        List<Map<String, Object>> results = new ArrayList<>();

        for (DictionaryCatalog.Definition dictionary : catalog.all()) {
            results.add(submitDictionary(dictionary.name(), request));
        }

        return results;
    }

    private Map<String, Object> submitDictionary(String name, Request request) {
        try {
            return Map.of(
                "entity", name,
                "runId", submit(name, request),
                "status", "queued"
            );
        } catch (DuplicateKeyException exception) {
            return Map.of("entity", name, "status", "already_active");
        } catch (RejectedExecutionException exception) {
            return Map.of("entity", name, "status", "queue_full");
        }
    }

    void execute(
        UUID runId,
        DictionaryCatalog.Definition dictionary,
        Request request
    ) {
        try (Connection connection = dataSource.getConnection()) {
            if (!lock(connection, dictionary.name(), true)) {
                store.finish(runId, "failed", "Справочник занят другим процессом");
                return;
            }

            try {
                if (store.start(runId)) {
                    synchronizeDictionary(runId, dictionary, request);
                }
            } catch (RuntimeException exception) {
                store.finish(runId, "failed", safeError(exception));
            } finally {
                lock(connection, dictionary.name(), false);
            }
        } catch (Exception exception) {
            store.finish(runId, "failed", "Не удалось получить/освободить соединение загрузки");
        }
    }

    private void synchronizeDictionary(
        UUID runId,
        DictionaryCatalog.Definition dictionary,
        Request request
    ) {
        JsonNode passport = source.passport(dictionary.oid(), request.version());
        String version = validatePassport(dictionary, passport, request.version());

        store.passport(runId, dictionary.name(), version, passport);
        loadVersions(runId, dictionary);

        if (!request.force() && version.equals(store.loadedVersion(dictionary.name()))) {
            store.finish(runId, "skipped", null);
            return;
        }

        validateMapping(dictionary, passport);
        long expectedRows = nonnegativeLong(passport.get("rowsCount"), "rowsCount паспорта");

        loadDataPages(runId, dictionary, version, expectedRows);
        verifyPassportUnchanged(dictionary, version, passport, expectedRows);
        applyService.apply(runId, dictionary, version, expectedRows, request.allowEmpty());
    }

    private void loadDataPages(
        UUID runId,
        DictionaryCatalog.Definition dictionary,
        String version,
        long expectedRows
    ) {
        long receivedRows = 0;
        int pageNumber = 0;

        do {
            if (pageNumber >= maxPages) {
                throw new IllegalArgumentException("Превышен лимит страниц");
            }

            JsonNode payload = source.page("data", dictionary.oid(), version, pageNumber, pageSize);
            JsonNode rows = requireList(payload);
            store.page(runId, "data", pageNumber, payload);

            boolean prematureEmptyPage = rows.isEmpty() && receivedRows < expectedRows;
            if (rows.size() > pageSize || prematureEmptyPage) {
                throw new IllegalArgumentException(
                    "Неполная/некорректная страница НСИ: " + pageNumber
                );
            }

            receivedRows += rows.size();
            if (receivedRows > expectedRows) {
                throw new IllegalArgumentException("Число строк превышает паспорт");
            }

            pageNumber++;
        } while (receivedRows < expectedRows);
    }

    private void verifyPassportUnchanged(
        DictionaryCatalog.Definition dictionary,
        String version,
        JsonNode originalPassport,
        long expectedRows
    ) {
        JsonNode currentPassport = source.passport(dictionary.oid(), version);
        validatePassport(dictionary, currentPassport, version);

        boolean rowCountChanged = nonnegativeLong(currentPassport.get("rowsCount"), "rowsCount")
            != expectedRows;
        boolean fieldsChanged = !Objects.equals(
            originalPassport.get("fields"), currentPassport.get("fields")
        );
        boolean updateTimeChanged = !Objects.equals(
            originalPassport.get("lastUpdate"), currentPassport.get("lastUpdate")
        );

        if (rowCountChanged || fieldsChanged || updateTimeChanged) {
            throw new IllegalArgumentException("Паспорт изменился во время загрузки");
        }
    }

    private void loadVersions(UUID runId, DictionaryCatalog.Definition dictionary) {
        long receivedVersions = 0;
        long expectedVersions = -1;
        Set<String> seenVersions = new HashSet<>();

        for (int pageNumber = 0; pageNumber < maxPages; pageNumber++) {
            JsonNode payload = source.page("versions", dictionary.oid(), null, pageNumber, pageSize);
            JsonNode versions = requireList(payload);
            store.page(runId, "versions", pageNumber, payload);

            long total = nonnegativeLong(payload.get("total"), "total списка версий");
            if (expectedVersions == -1) {
                expectedVersions = total;
            }

            boolean prematureEmptyPage = versions.isEmpty() && receivedVersions < expectedVersions;
            if (total != expectedVersions || versions.size() > pageSize || prematureEmptyPage) {
                throw new IllegalArgumentException(
                    "Список версий изменился или получен не полностью"
                );
            }

            saveMissingPassports(dictionary, versions, seenVersions);
            store.versions(dictionary.name(), versions);
            receivedVersions += versions.size();

            if (receivedVersions > expectedVersions) {
                throw new IllegalArgumentException("Неверное число версий");
            }
            if (receivedVersions == expectedVersions) {
                return;
            }
        }

        throw new IllegalArgumentException("Превышен лимит страниц версий");
    }

    private void saveMissingPassports(
        DictionaryCatalog.Definition dictionary,
        JsonNode versions,
        Set<String> seenVersions
    ) {
        for (JsonNode item : versions) {
            String version = item.path("version").asText("");

            if (version.isBlank() || !seenVersions.add(version)) {
                throw new IllegalArgumentException("Повторная/пустая версия в НСИ");
            }

            if (!store.hasPassport(dictionary.name(), version)) {
                JsonNode passport = source.passport(dictionary.oid(), version);
                validatePassport(dictionary, passport, version);
                store.savePassport(dictionary.name(), version, passport);
            }
        }
    }

    static JsonNode requireList(JsonNode payload) {
        JsonNode list = payload.get("list");

        if (list == null || !list.isArray()) {
            throw new IllegalArgumentException("В ответе НСИ отсутствует list");
        }

        return list;
    }

    static String validatePassport(
        DictionaryCatalog.Definition dictionary,
        JsonNode passport,
        String requestedVersion
    ) {
        if (!dictionary.oid().equals(passport.path("oid").asText())) {
            throw new IllegalArgumentException("Паспорт другого OID");
        }

        String version = passport.path("version").asText("");
        boolean wrongVersion = requestedVersion != null && !requestedVersion.equals(version);

        if (version.isBlank() || version.length() > MAX_VERSION_LENGTH || wrongVersion) {
            throw new IllegalArgumentException("НСИ вернул неверную версию паспорта");
        }

        return version;
    }

    static void validateMapping(DictionaryCatalog.Definition dictionary, JsonNode passport) {
        Set<String> fields = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);

        for (JsonNode field : passport.path("fields")) {
            fields.add(field.path("field").asText(""));
        }

        for (DictionaryCatalog.Column column : dictionary.columns()) {
            if (!fields.contains(column.source())) {
                throw new IllegalArgumentException(
                    "Поле отсутствует в паспорте: " + column.source()
                        + "; проверьте dictionary-catalog.json"
                );
            }
        }
    }

    static long nonnegativeLong(JsonNode value, String label) {
        if (value == null || !value.isIntegralNumber()
            || !value.canConvertToLong() || value.longValue() < 0) {
            throw new IllegalArgumentException("Некорректный " + label);
        }

        return value.longValue();
    }

    static String safeError(RuntimeException exception) {
        if (exception instanceof DataAccessException) {
            return "Ошибка SQL: тип, ограничение или структура таблицы. "
                + "Изменения справочника отменены; исходные страницы сохранены.";
        }

        if (exception instanceof IllegalArgumentException || exception instanceof IllegalStateException) {
            String message = exception.getMessage();
            if (message == null) {
                return "Ошибка загрузки";
            }
            return message.substring(0, Math.min(MAX_ERROR_LENGTH, message.length()));
        }

        return "Непредвиденная ошибка загрузки: " + exception.getClass().getSimpleName();
    }

    private boolean lock(Connection connection, String name, boolean acquire) throws SQLException {
        String function = acquire ? "pg_try_advisory_lock" : "pg_advisory_unlock";
        String sql = "SELECT " + function + "(hashtextextended(?, 0))";

        try (var statement = connection.prepareStatement(sql)) {
            statement.setString(1, "nsi.sync." + name);

            try (var result = statement.executeQuery()) {
                result.next();
                return result.getBoolean(1);
            }
        }
    }

    public void recover(UUID runId) {
        Map<String, Object> run = store.run(runId);
        String name = (String) run.get("entity_name");

        try (Connection connection = dataSource.getConnection()) {
            if (!lock(connection, name, true)) {
                throw new IllegalStateException("Загрузка ещё выполняется");
            }

            try {
                store.finish(
                    runId,
                    "interrupted",
                    "Загрузка прервана оператором; можно запустить повторно"
                );
            } finally {
                lock(connection, name, false);
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Не удалось проверить блокировку");
        }
    }

    @PreDestroy
    public void shutdown() {
        executor.shutdown();

        try {
            if (!executor.awaitTermination(20, TimeUnit.SECONDS)) {
                executor.shutdownNow();
            }
        } catch (InterruptedException exception) {
            executor.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }
}
