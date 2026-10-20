package com.example.app.loading.services;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.example.app.loading.dto.DirectionTypeLoadResultDTO;
import com.example.app.loading.repos.DsaLoadBatchJdbcRepository;

import lombok.extern.log4j.Log4j2;

@Log4j2
@Service
public class DirectionTypeLoadService {

    private final JdbcTemplate jdbcTemplate;
    private final DsaLoadBatchJdbcRepository batchRepository;

    public DirectionTypeLoadService(
        JdbcTemplate jdbcTemplate,
        DsaLoadBatchJdbcRepository batchRepository
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.batchRepository = batchRepository;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public DirectionTypeLoadResultDTO loadDirectionType(
        Long userId,
        String version,
        String sourceUrl
    ) {
        if (userId == null) {
            throw new IllegalArgumentException("userId обязателен");
        }

        if (version == null || version.isBlank() || version.length() > 100) {
            throw new IllegalArgumentException(
                "Версия обязательна и не должна превышать 100 символов"
            );
        }

        if (sourceUrl == null || sourceUrl.isBlank() || sourceUrl.length() > 500) {
            throw new IllegalArgumentException(
                "URL источника обязателен и не должен превышать 500 символов"
            );
        }

        Long batchId = jdbcTemplate.queryForObject(
            """
            CALL dsa_data_load.load_direction_type(
                ?,
                ?,
                ?,
                NULL::bigint
            )
            """,
            (rs, rowNum) -> {
                long id = rs.getLong("p_batch_id");
                return rs.wasNull() ? null : id;
            },
            userId,
            version,
            sourceUrl
        );

        if (batchId == null) {
            throw new IllegalStateException(
                "Процедура не вернула идентификатор загрузки"
            );
        }

        DirectionTypeLoadResultDTO result =
            batchRepository.findDirectionTypeResult(batchId);

        log.info(
            "Результат процедуры: batchId={}, status={}, "
                + "inserted={}, updated={}, deleted={}, rejected={}",
            result.batchId(),
            result.status(),
            result.rowsInserted(),
            result.rowsUpdated(),
            result.rowsDeleted(),
            result.rowsRejected()
        );

        return result;
    }
}