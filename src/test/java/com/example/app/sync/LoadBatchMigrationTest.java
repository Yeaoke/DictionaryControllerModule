package com.example.app.sync;

import static org.junit.jupiter.api.Assertions.*;

import java.util.UUID;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

@EnabledIfEnvironmentVariable(named = "TEST_DATABASE_URL", matches = ".+")
class LoadBatchMigrationTest {

    @Test
    void preservesLegacyBatchesRunsAndPageReferences() {
        String url = System.getenv("TEST_DATABASE_URL");
        String user = System.getenv().getOrDefault("TEST_DATABASE_USER", "nsi_test");
        String password = System.getenv().getOrDefault("TEST_DATABASE_PASSWORD", "");
        JdbcTemplate admin = new JdbcTemplate(new DriverManagerDataSource(url, user, password));
        String database = "migration_" + UUID.randomUUID().toString().replace("-", "");
        admin.execute("CREATE DATABASE " + database);

        try {
            String testUrl = url.substring(0, url.lastIndexOf('/') + 1) + database;
            Flyway.configure().locations("classpath:db/migrations").dataSource(testUrl, user, password)
                .defaultSchema("data").schemas("data").target("6").load().migrate();
            JdbcTemplate jdbc = new JdbcTemplate(new DriverManagerDataSource(testUrl, user, password));
            Long legacyId = jdbc.queryForObject("""
                INSERT INTO data.dsa_load_batch (
                    data_source, data_source_url, entity_name, dsa_table_name,
                    data_table_name, load_type, load_procedure_name, status
                ) VALUES ('minzdrav', 'test', 'direction_type', 'dsa_raw_direction_type',
                    'direction_type', 'full', 'legacy', 'success')
                RETURNING id
                """, Long.class);
            UUID runId = UUID.randomUUID();
            jdbc.update("""
                INSERT INTO data.nsi_sync_run (
                    id, entity_name, oid, source_version, user_id, status, rows_received
                ) VALUES (?, 'direction_type', '1.2.3', '42', 1, 'running', 3)
                """, runId);
            jdbc.update("""
                INSERT INTO data.nsi_sync_page VALUES (?, 'data', 0, '{"list":[]}'::jsonb)
                """, runId);

            Flyway.configure().locations("classpath:db/migrations").dataSource(testUrl, user, password)
                .defaultSchema("data").schemas("data").load().migrate();

            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM data.dsa_load_batch", Integer.class));
            assertEquals("legacy", jdbc.queryForObject(
                "SELECT load_procedure_name FROM data.dsa_load_batch WHERE id=?", String.class, legacyId));
            assertEquals("42", jdbc.queryForObject(
                "SELECT new_version FROM data.dsa_load_batch WHERE run_id=?", String.class, runId));
            assertEquals(3L, jdbc.queryForObject(
                "SELECT rows_extracted FROM data.dsa_load_batch WHERE run_id=?", Long.class, runId));
            assertEquals(1, jdbc.queryForObject("""
                SELECT count(*) FROM data.nsi_sync_page p
                JOIN data.dsa_load_batch b ON b.run_id=p.run_id WHERE b.run_id=?
                """, Integer.class, runId));
            assertNull(jdbc.queryForObject("SELECT to_regclass('data.nsi_sync_run')", String.class));
            assertThrows(org.springframework.dao.DataIntegrityViolationException.class,
                () -> jdbc.update("DELETE FROM data.dsa_load_batch WHERE run_id=?", runId));
        } finally {
            admin.execute("DROP DATABASE " + database);
        }
    }
}

