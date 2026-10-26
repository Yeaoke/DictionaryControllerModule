package com.example.app.loading.services;

import java.sql.Types;
import java.util.*;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.example.app.loading.config.DictionaryRegistry;
import com.example.app.loading.config.DictionaryLoadProperties;
import org.springframework.beans.factory.annotation.Autowired;
import com.example.app.loading.dto.DictionarySnapshot;
import com.example.app.loading.dto.DictionaryLoadResultDTO;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;

@Service
public class DictionaryApplyService {

    private final JdbcTemplate jdbc;
    private final DictionaryRegistry registry;
    private final DictionaryRowMapper mapper;
    private final DictionarySchemaValidator schema;
    private final LoadedVersionJdbcRepository versions;
    private final DictionaryProcedureService procedures;
    private final DictionaryLoadProperties properties;
    
    public DictionaryApplyService(
        JdbcTemplate jdbc,
        DictionaryRegistry registry,
        DictionaryRowMapper mapper,    
        DictionarySchemaValidator schema,
        LoadedVersionJdbcRepository versions,
        DictionaryProcedureService procedures
    ) {
        this(jdbc, registry, mapper, schema, versions, procedures, DictionaryLoadProperties.defaults());
    }

    @Autowired
    public DictionaryApplyService(JdbcTemplate jdbc, DictionaryRegistry registry, DictionaryRowMapper mapper,
            DictionarySchemaValidator schema, LoadedVersionJdbcRepository versions,
            DictionaryProcedureService procedures, DictionaryLoadProperties properties) {
        this.jdbc = jdbc;
        this.registry = registry;
        this.mapper = mapper;
        this.schema = schema;
        this.versions = versions;
        this.procedures = procedures;
        this.properties = properties;
    }

    @Transactional
    public Optional<DictionaryLoadResultDTO> apply(
        DictionarySnapshot snapshot,
        Long userId,
        String sourceUrl,
        String expectedVersion
    ) {        
        if (snapshot == null || userId == null || sourceUrl == null || sourceUrl.isBlank() || sourceUrl.length() > 500) {
            throw new IllegalArgumentException("Snapshot, userId and source URL (max 500) required");
        }
        
        var d = registry.require(snapshot.oid());
        
        mapper.validateSnapshot(d, snapshot);
        
        schema.validate(d);
        
        jdbc.query("SELECT pg_advisory_xact_lock(hashtextextended(?,0))", rs -> {}, "dsa_data_load." + d.entityName());
        
        String current = versions.findVersionByEntityName(d.entityName()).orElse(null);
        
        if (snapshot.version().equals(current)) {
            return Optional.empty();
        }
        
        if (!Objects.equals(current, expectedVersion)) {
            throw new IllegalStateException("Loaded version changed; restart import");
        }
        jdbc.execute("LOCK TABLE " + d.stagingTable() + " IN SHARE ROW EXCLUSIVE MODE");
        jdbc.update("DELETE FROM " + d.stagingTable());
        
        String columns = d.columns().stream().map(c -> c.target()).collect(Collectors.joining(","));
        
        String placeholders = String.join(",", Collections.nCopies(d.columns().size(), "?"));
        
        String sql = "INSERT INTO " + d.stagingTable() + " (" + columns + ") VALUES (" + placeholders + ")";
        int[] jdbcTypes = d.columns().stream().mapToInt(c -> switch (c.type()) {
            case LONG -> Types.BIGINT; case INTEGER -> Types.INTEGER; case STRING -> Types.VARCHAR;
            case DECIMAL -> Types.NUMERIC; case BOOLEAN -> Types.BOOLEAN; case DATE -> Types.DATE;
            case TIMESTAMP -> Types.TIMESTAMP;
        }).toArray();
        // Conversion failures in later batches still roll back all staging writes.
        mapper.forEachBatch(d, snapshot, properties.jdbcBatchSize(), rows ->
            jdbc.batchUpdate(sql, rows, properties.jdbcBatchSize(),
            (ps, row) -> {
                for (int i = 0; i < row.size(); i++) {
                    ps.setObject(i + 1, row.get(i), jdbcTypes[i]);
                }
            }));
            
        return Optional.of(procedures.load(d, userId, snapshot.version(), sourceUrl));
    }
}
