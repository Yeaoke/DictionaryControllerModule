package com.example.app.conrollerversion;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.flywaydb.core.Flyway;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;
import static org.assertj.core.api.Assertions.*;

@org.springframework.test.context.ActiveProfiles("integration")
@SpringBootTest
@TestPropertySource(properties = {
    "spring.datasource.url=${TEST_POSTGRES_URL}",
    "spring.datasource.username=${TEST_POSTGRES_USERNAME}",
    "spring.datasource.password=${TEST_POSTGRES_PASSWORD}",
    "nsi.minzdrav.user-key=test-key"
})
class DatabaseMigrationIT {

    @Autowired JdbcTemplate jdbc;
    @Autowired Flyway flyway;
    @Autowired LoadedVersionJdbcRepository versions;

    @Test
    void migratesAllTablesAndDoesNotReapplyMigrations() {
        assertThat(jdbc.queryForObject(
            "select count(*) from information_schema.tables where table_schema = 'data' and table_name <> 'flyway_schema_history'",
            Integer.class)).isEqualTo(130);
        assertThat(flyway.migrate().migrationsExecuted).isZero();
    }

    @Test
    void everyDictionaryHasAStagingTableWithMatchingSourceTypes() {
        var dictionaries = jdbc.queryForList("""
            select table_name from information_schema.tables
            where table_schema = 'data' and table_name not like 'dsa_%' and table_name <> 'flyway_schema_history'
            order by table_name
            """, String.class);
        assertThat(dictionaries).hasSize(64);
        for (String dictionary : dictionaries) {
            assertThat(jdbc.queryForObject(
                "select to_regclass(?)::text", String.class, "data.dsa_raw_" + dictionary))
                .as("staging table for %s", dictionary).isNotNull();
        }
        // direction_type retains its earlier source-specific contract (doc/sort).
        assertThat(jdbc.queryForList("""
            select t.relname || '.' || a.attname as mismatch
            from pg_class t
            join pg_namespace n on n.oid = t.relnamespace
            join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
            left join pg_class r on r.relnamespace = n.oid and r.relname = 'dsa_raw_' || t.relname
            left join pg_attribute b on b.attrelid = r.oid and b.attname = a.attname and not b.attisdropped
            where n.nspname = 'data' and t.relkind = 'r'
              and t.relname not like 'dsa_%' and t.relname not in ('direction_type', 'flyway_schema_history')
              and a.attname not in ('is_deleted', 'search_synonym')
              and (b.attname is null or a.atttypid <> b.atttypid
                   or a.atttypmod <> b.atttypmod or b.attnotnull)
            """, String.class)).isEmpty();
        assertThat(jdbc.queryForObject("""
            select count(*) from information_schema.columns
            where table_schema = 'data' and table_name like 'dsa_raw_%'
              and column_name = 'raw_row_id' and is_identity = 'YES'
            """, Integer.class)).isEqualTo(63);
    }

    @Test
    @org.springframework.transaction.annotation.Transactional
    void stagingRetainsDuplicatesMissingFieldsAndDifferentKeyShapes() {
        jdbc.execute("""
            insert into data.dsa_raw_patient_sex(id, name, reject_reason)
            values (42, null, 'Missing name'), (42, 'Duplicate', 'Duplicate source ID')
            """);
        assertThat(jdbc.queryForObject(
            "select count(distinct raw_row_id) from data.dsa_raw_patient_sex where id=42",
            Integer.class)).isEqualTo(2);
        jdbc.execute("""
            insert into data.dsa_raw_laboratory_test(id, new_id)
            values ('001-A', '001-A')
            """);
        assertThat(jdbc.queryForObject(
            "select new_id from data.dsa_raw_laboratory_test where id='001-A'",
            String.class)).isEqualTo("001-A");
        jdbc.execute("""
            insert into data.dsa_raw_foms_bill_type(code, region_okato_code, new_key)
            values ('01', '001', '{"code":"01","region_okato_code":"001"}'::jsonb)
            """);
        assertThat(jdbc.queryForObject(
            "select new_key->>'region_okato_code' from data.dsa_raw_foms_bill_type where code='01'",
            String.class)).isEqualTo("001");
        // Domain CHECK restrictions remain in accepted tables, not in staging.
        jdbc.execute("insert into data.dsa_raw_bed_profile(id, age_group) values (42, 999)");
        assertThat(jdbc.queryForObject(
            "select age_group from data.dsa_raw_bed_profile where id=42",
            Integer.class)).isEqualTo(999);
    }

    @Test
    @org.springframework.transaction.annotation.Transactional
    void generatesBatchTimestampAndReturnsItThroughJdbc() {
        var result = jdbc.queryForMap("""
            INSERT INTO data.dsa_load_batch (
                data_source, data_source_url, entity_name, dsa_table_name,
                data_table_name, load_type, load_procedure_name, status
            ) VALUES ('minzdrav', 'https://example.test', 'test',
                'dsa_raw_direction_type', 'direction_type', 'FULL', 'test', 'STARTED')
            RETURNING id, started_at
            """);
        assertThat(((Number) result.get("id")).longValue()).isPositive();
        assertThat(result.get("started_at")).isNotNull();
    }

    @Test
    @org.springframework.transaction.annotation.Transactional
    void jdbcRepositoryReadsExistingVersionAndHandlesMissingDictionary() {
        String entity = "test-" + java.util.UUID.randomUUID();
        assertThat(versions.findVersionByEntityName(entity)).isEmpty();
        jdbc.update("insert into data.dsa_loaded_version(entity_name, version) values (?, ?)", entity, "1.2");
        assertThat(versions.findVersionByEntityName(entity)).contains("1.2");
        assertThat(versions.findVersionByEntityName("' OR '1'='1")).isEmpty();
    }

    @Test
    void preventsDuplicateDictionaryVersions() {
        String entity = "test-" + java.util.UUID.randomUUID();
        try {
            jdbc.update("insert into data.dsa_loaded_version(entity_name, version) values (?, ?)", entity, "1");
            assertThatThrownBy(() -> jdbc.update(
                "insert into data.dsa_loaded_version(entity_name, version) values (?, ?)", entity, "2"))
                .isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
        } finally {
            jdbc.update("delete from data.dsa_loaded_version where entity_name = ?", entity);
        }
    }

}
