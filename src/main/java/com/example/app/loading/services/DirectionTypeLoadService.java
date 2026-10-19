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
        Long userId,
        String version,
        String sourceUrl
    ) {
        if (userId == null) {
            throw new IllegalArgumentException(
                "ФОМС userId не должен быть null"
            );
        }
        
        jdbcTemplate.update(
            "CALL dsa_data_load.load_direction_type(?, ?, ?)",
            userId,
            version,
            sourceUrl
        );
        log.info("Процедура загрузка справочника завершена успешно для версии {}", version);
    }
}
