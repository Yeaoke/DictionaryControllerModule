package com.example.app.loading.repos;

import java.util.Optional;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class LoadedVersionJdbcRepository {

    private final JdbcTemplate jdbcTemplate;

    public LoadedVersionJdbcRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public Optional<String> findVersionByEntityName(String entityName) {
        return jdbcTemplate.query(
            """
            SELECT version
            FROM data.dsa_loaded_version
            WHERE entity_name = ?
            """,
            (rs, rowNum) -> rs.getString("version"),
            entityName
        ).stream().findFirst();
    }
}