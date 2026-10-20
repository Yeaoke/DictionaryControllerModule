package com.example.app.staging.repos;

import java.math.BigDecimal;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import com.example.app.dictionary.dto.DirectionTypeRowDTO;

@Repository
public class DirectionTypeStagingJdbcRepository {

    private static final String INSERT_SQL = """
        INSERT INTO data.dsa_raw_direction_type (
            id,
            name,
            doc,
            sort,
            reject_reason,
            new_id
        )
        VALUES (?, ?, ?, ?, NULL, NULL)
        """;

    private final JdbcTemplate jdbcTemplate;

    public DirectionTypeStagingJdbcRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public void replaceAll(List<DirectionTypeRowDTO> rows) {
        validateRows(rows);

        jdbcTemplate.execute("""
            DO $$
            BEGIN
                PERFORM pg_advisory_xact_lock(
                    hashtextextended('dsa_data_load.direction_type', 0)
                );
            END;
            $$
            """);

        jdbcTemplate.execute("""
            LOCK TABLE data.dsa_raw_direction_type
            IN SHARE ROW EXCLUSIVE MODE
            """);

        jdbcTemplate.update("DELETE FROM data.dsa_raw_direction_type");

        jdbcTemplate.batchUpdate(INSERT_SQL, rows, 500, (statement, row) -> {
                statement.setLong(1, row.id());
                statement.setString(2, row.name());
                statement.setString(3, row.doc());

                if (row.sort() == null) {
                    statement.setNull(4, java.sql.Types.NUMERIC);
                } else {
                    statement.setBigDecimal(4, BigDecimal.valueOf(row.sort()));
                }
            }
        );
    }

    private void validateRows(List<DirectionTypeRowDTO> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new IllegalArgumentException(
                "Нельзя заменить staging пустым набором"
            );
        }

        Set<Long> ids = new HashSet<>();

        for (DirectionTypeRowDTO row : rows) {
            if (row == null || row.id() == null) {
                throw new IllegalArgumentException(
                    "Каждая строка должна содержать ID"
                );
            }

            if (!ids.add(row.id())) {
                throw new IllegalArgumentException(
                    "Повторяющийся ID: " + row.id()
                );
            }

            if (row.name() == null || row.name().isBlank()) {
                throw new IllegalArgumentException(
                    "Отсутствует название для ID=" + row.id()
                );
            }

            validateLength(row.name(), 100, "name", row.id());
            validateLength(row.doc(), 100, "doc", row.id());

            if (row.sort() != null && (row.sort() < -9_999_999_999L || row.sort() > 9_999_999_999L)) {

                throw new IllegalArgumentException(
                    "Поле sort не помещается в numeric(10), ID=" + row.id()
                );
            }

            if (row.rejectReason() != null && !row.rejectReason().isBlank()) {

                throw new IllegalArgumentException(
                    "Набор содержит отклонённую запись, ID=" + row.id()
                );
            }
        }
    }

    private void validateLength(
        String value,
        int maxLength,
        String field,
        Long id
    ) {
        if (value != null
            && value.codePointCount(0, value.length()) > maxLength) {

            throw new IllegalArgumentException(
                "Поле " + field + " превышает " + maxLength
                    + " символов, ID=" + id
            );
        }
    }
}