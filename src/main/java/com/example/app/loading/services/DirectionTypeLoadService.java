package com.example.app.loading.services;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import lombok.extern.log4j.Log4j2;

@Log4j2
@Service
public class DirectionTypeLoadService {
    
    private final JdbcTemplate jdbcTemplate;

    public DirectionTypeLoadService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public void loadDirectionType(
        String userKey,
        String version,
        String sourceUrl
    ) {
        log.info("Loading data to direction_type");
        jdbcTemplate.update(
            "CALL dsa_data_load.load_direction_type(?, ?, ?)",
            userKey,
            version,
            sourceUrl
        );
    }
}
