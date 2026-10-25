package com.example.app.loading.services;

import java.time.OffsetDateTime;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import com.example.app.loading.dto.DictionaryLoadResultDTO;

@Service
public class DictionaryProcedureService {

    private final JdbcTemplate jdbc;
    
    public DictionaryProcedureService(
        JdbcTemplate jdbc
    ) {
        this.jdbc = jdbc;
    }
    
    @Transactional(propagation = Propagation.MANDATORY)
    public DictionaryLoadResultDTO load(
        com.example.app.loading.config.DictionaryCatalog.Definition definition,
        Long userId,
        String version,
        String sourceUrl
    ) {
        if (userId == null || version == null || version.isBlank() || version.length() > 100 || sourceUrl == null || sourceUrl.isBlank() || sourceUrl.length() > 500) {
            throw new IllegalArgumentException("userId, version (max 100), sourceUrl (max 500) required");
        }
        Long batchId = jdbc.queryForObject("CALL " + definition.procedure() + "(?, ?, ?, NULL::bigint)", (rs, index) -> rs.getObject("p_batch_id", Long.class), userId, version, sourceUrl);
        if (batchId == null) {
            throw new IllegalStateException("Procedure returned no batch ID");
        }
        return jdbc.queryForObject("SELECT * FROM data.dsa_load_batch WHERE id=? AND entity_name=?",
            (rs, index) -> new DictionaryLoadResultDTO(
                rs.getLong("id"), rs.getString("entity_name"), rs.getString("data_source"),
                rs.getString("current_version"), rs.getString("new_version"), rs.getString("status"),
                rs.getObject("started_at", OffsetDateTime.class), rs.getObject("finished_at", OffsetDateTime.class),
                rs.getLong("rows_current"), rs.getLong("rows_current_deleted"), rs.getLong("rows_extracted"),
                rs.getLong("rows_rejected"), rs.getLong("rows_inserted"), rs.getLong("rows_updated"),
                rs.getLong("rows_deleted"), rs.getLong("rows_new"), rs.getLong("rows_new_deleted"),
                rs.getString("error_message")), batchId, definition.entityName());
    }
}
