package com.example.app.loading.repos;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import com.example.app.loading.dto.DirectionTypeLoadResultDTO;

@Repository
public class DsaLoadBatchJdbcRepository {

    private final JdbcTemplate jdbcTemplate;

    public DsaLoadBatchJdbcRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public DirectionTypeLoadResultDTO findDirectionTypeResult(long batchId) {
        return jdbcTemplate.queryForObject(
            """
            SELECT
                id,
                entity_name,
                data_source,
                current_version,
                new_version,
                status,
                started_at,
                finished_at,
                rows_current,
                rows_current_deleted,
                rows_extracted,
                rows_rejected,
                rows_inserted,
                rows_updated,
                rows_deleted,
                rows_new,
                rows_new_deleted,
                error_message
            FROM data.dsa_load_batch
            WHERE id = ?
              AND entity_name = 'direction_type'
            """,
            (rs, rowNum) -> new DirectionTypeLoadResultDTO(
                rs.getLong("id"),
                rs.getString("entity_name"),
                rs.getString("data_source"),
                rs.getString("current_version"),
                rs.getString("new_version"),
                rs.getString("status"),
                rs.getObject("started_at", OffsetDateTime.class),
                rs.getObject("finished_at", OffsetDateTime.class),
                readCount(rs, "rows_current"),
                readCount(rs, "rows_current_deleted"),
                readCount(rs, "rows_extracted"),
                readCount(rs, "rows_rejected"),
                readCount(rs, "rows_inserted"),
                readCount(rs, "rows_updated"),
                readCount(rs, "rows_deleted"),
                readCount(rs, "rows_new"),
                readCount(rs, "rows_new_deleted"),
                rs.getString("error_message")
            ),
            batchId
        );
    }

    private static Long readCount(
        ResultSet rs,
        String column
    ) throws SQLException {
        BigDecimal value = rs.getBigDecimal(column);
        return value == null ? null : value.longValueExact();
    }
}