package com.example.app.staging.repos;

import java.sql.Types;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import com.example.app.loading.dto.DirectionTypeSnapshot;

@Repository
public class DirectionTypeStagingJdbcRepository {
    private final JdbcTemplate jdbc;

    public DirectionTypeStagingJdbcRepository(
        JdbcTemplate jdbc
    ) {
        this.jdbc = jdbc;
    }
    
    @Transactional(propagation = Propagation.MANDATORY)
    public void replaceAll(
        DirectionTypeSnapshot snapshot
    ) {
        jdbc.execute("LOCK TABLE data.dsa_raw_direction_type IN SHARE ROW EXCLUSIVE MODE");
        jdbc.update("DELETE FROM data.dsa_raw_direction_type");
        jdbc.batchUpdate("INSERT INTO data.dsa_raw_direction_type(id,name,doc,sort) VALUES (?,?,?,?)",
            snapshot.rows(), 500, (ps, row) -> {
                ps.setLong(1, row.id()); ps.setString(2, row.name()); ps.setString(3, row.doc());
                if (row.sort() == null) {
                    ps.setNull(4, Types.NUMERIC);
                } else { 
                    ps.setBigDecimal(4, java.math.BigDecimal.valueOf(row.sort()));
                }
            });
    }
}
