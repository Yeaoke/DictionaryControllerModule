package com.example.app.loading.services;

import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.DeserializationFeature;
import com.example.app.integration.nsi.client.NsiMizdravClient;
import com.example.app.loading.config.DictionaryRegistry;
import com.example.app.loading.dto.*;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;

@Service
@Transactional(propagation = Propagation.NEVER)
public class DictionaryImportService {

    private final DictionaryRegistry registry;
    private final DictionarySchemaValidator schema;
    private final NsiMizdravClient client;
    private final LoadedVersionJdbcRepository versions;
    private final DictionaryApplyService apply;
    private final String baseUrl;

    private final JsonMapper json = JsonMapper.builder().enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).build();
    
    public DictionaryImportService(
        DictionaryRegistry registry,
        DictionarySchemaValidator schema,
        NsiMizdravClient client,
        LoadedVersionJdbcRepository versions,
        DictionaryApplyService apply,
        @Value("${nsi.minzdrav.base-url}") String baseUrl
    ) {
        this.registry = registry;
        this.schema = schema;
        this.client = client;
        this.versions = versions;
        this.apply = apply;
        this.baseUrl = baseUrl;
    }

    public Optional<DictionaryLoadResultDTO> load(
        String oid,
        Long userId
    ) {
        if (userId == null) {
            throw new IllegalArgumentException("userId required");
        }
        
        var d = registry.require(oid);
        
        schema.validate(d);
        String expected = versions.findVersionByEntityName(d.entityName()).orElse(null);
        var passport = client.getPassport(oid);
        
        if (passport == null || !oid.equals(passport.oid()) || passport.version() == null || passport.version().isBlank() || passport.rowsCount() == null || passport.rowsCount() < 1 || passport.rowsCount() > 100000) {
            throw new IllegalStateException("Invalid passport OID/version/count");
        }
        if (passport.version().equals(expected)) {
            return Optional.empty();
        }
        
        var rows = new ArrayList<Map<String, JsonNode>>();
        
        var seen = new HashSet<List<JsonNode>>();
        
        var keySources = d.columns().stream().filter(c -> d.keyColumns().contains(c.target())).map(c -> c.source()).toList();
        
        for (int page = 1; rows.size() < passport.rowsCount(); page++) {
            var response = client.getData(oid, passport.version(), page, 500, d.sorting(), "ASC");
            if (response == null || response.total() == null || response.total().longValue() != passport.rowsCount() || response.list() == null || response.list().isEmpty() || response.list().size() > 500) {
                throw new IllegalStateException("Incomplete NSI page " + page);
            }
            for (var sourceRow : response.list()) {
                if (sourceRow == null) {
                    throw new IllegalStateException("Null NSI row");
                }
                var row = new HashMap<String, JsonNode>();
                for (var item : sourceRow) {
                    if (item == null || item.column() == null || row.containsKey(item.column())) {
                        throw new IllegalStateException("Missing/duplicate NSI column");
                    }
                    row.put(item.column(), item.value());
                }
                if (!seen.add(keySources.stream().map(row::get).toList())) {
                    throw new IllegalStateException("Repeated NSI key/page");
                }
                rows.add(row);
            }
            if (rows.size() > passport.rowsCount()) {
                throw new IllegalStateException("NSI count changed");
            }
        }
        var after = client.getPassport(oid);
        if (after == null || !oid.equals(after.oid()) || !passport.version().equals(after.version()) || !passport.rowsCount().equals(after.rowsCount())) {
            throw new IllegalStateException("NSI passport changed; retry");
        }

        return apply.apply(new DictionarySnapshot(oid, passport.version(), passport.rowsCount(), rows), userId, baseUrl + "/rest/data?identifier=" + oid, expected);
    }
    public Optional<DictionaryLoadResultDTO> loadFile(String oid, Path file, Long userId) throws IOException {
        if (userId == null) {
            throw new IllegalArgumentException("userId required");
        }
        
        var d = registry.require(oid);
        schema.validate(d);
        
        String expected = versions.findVersionByEntityName(d.entityName()).orElse(null);
        
        byte[] bytes;
        
        try (var in = Files.newInputStream(file)) {
            bytes = in.readNBytes(20 * 1024 * 1024 + 1);
        }
        
        if (bytes.length > 20 * 1024 * 1024) {
            throw new IllegalArgumentException("File exceeds 20 MiB");
        }
        
        var snapshot = json.readValue(bytes, DictionarySnapshot.class);
        
        if (snapshot == null || !oid.equals(snapshot.oid())) {
            throw new IllegalArgumentException("File OID differs from requested OID");
        }
        
        return apply.apply(snapshot, userId, file.toAbsolutePath().normalize().toUri().toString(), expected);
    }
}
