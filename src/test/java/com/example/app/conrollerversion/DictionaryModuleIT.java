package com.example.app.conrollerversion;

import java.nio.file.Path;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import tools.jackson.databind.json.JsonMapper;
import com.example.app.loading.services.*;
import com.example.app.loading.dto.DictionarySnapshot;
import static org.assertj.core.api.Assertions.*;

@org.springframework.test.context.ActiveProfiles("integration")
@SpringBootTest
@TestPropertySource(properties = {
    "spring.datasource.url=${TEST_POSTGRES_URL}", "spring.datasource.username=${TEST_POSTGRES_USERNAME}",
    "spring.datasource.password=${TEST_POSTGRES_PASSWORD}", "nsi.minzdrav.user-key=test-key"
})
class DictionaryModuleIT {
    static com.sun.net.httpserver.HttpServer nsiServer;
    static final java.util.concurrent.atomic.AtomicInteger dataRequests = new java.util.concurrent.atomic.AtomicInteger();

    @org.springframework.test.context.DynamicPropertySource
    static void localNsi(org.springframework.test.context.DynamicPropertyRegistry properties) throws Exception {
        nsiServer = com.sun.net.httpserver.HttpServer.create(new java.net.InetSocketAddress("127.0.0.1", 0), 0);
        nsiServer.createContext("/rest/passport", exchange -> respond(exchange,
            "{\"result\":\"OK\",\"oid\":\"1.2.643.5.1.13.13.11.1040\",\"version\":\"test-http\",\"rowsCount\":2}"));
        nsiServer.createContext("/rest/data", exchange -> {
            dataRequests.incrementAndGet();
            if (!exchange.getRequestURI().getRawQuery().contains("version=test-http")) {
                exchange.sendResponseHeaders(400, -1); exchange.close(); return;
            }
            respond(exchange, "{\"result\":\"OK\",\"total\":2,\"list\":[[{\"column\":\"ID\",\"value\":1},{\"column\":\"NAME\",\"value\":\"One\"}],[{\"column\":\"ID\",\"value\":2},{\"column\":\"NAME\",\"value\":\"Two\"}]]}");
        });
        nsiServer.start();
        properties.add("nsi.minzdrav.base-url", () -> "http://127.0.0.1:" + nsiServer.getAddress().getPort());
    }

    static void respond(com.sun.net.httpserver.HttpExchange exchange, String json) throws java.io.IOException {
        byte[] bytes = json.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(200, bytes.length);
        try (var out = exchange.getResponseBody()) { out.write(bytes); }
    }

    @AfterAll static void stopLocalNsi() { if (nsiServer != null) nsiServer.stop(0); }

    @Test void importsThroughHttpAndSkipsSecondDownloadOfSameVersion() {
        int before = dataRequests.get();
        var result = imports.load(SEX, 7L).orElseThrow();
        assertThat(result.status()).isEqualTo("success");
        assertThat(result.rowsInserted()).isEqualTo(2);
        assertThat(imports.load(SEX, 7L)).isEmpty();
        assertThat(dataRequests.get() - before).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_load_batch", Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("select version from data.dsa_loaded_version where entity_name='patient_sex'", String.class)).isEqualTo("test-http");
    }
    @Autowired JdbcTemplate jdbc;
    @Autowired DictionaryImportService imports;
    @Autowired DictionaryApplyService apply;
    static final String DIRECTION = "1.2.643.5.1.13.13.11.1009";
    static final String SEX = "1.2.643.5.1.13.13.11.1040";

    @BeforeEach void fixtures() {
        jdbc.execute("create schema if not exists access_work");
        jdbc.execute("create view access_work.users_v as select 7::bigint id, 'Test user'::varchar full_name");
        jdbc.execute("create table data.log_level(id bigint primary key,sys_name text)");
        jdbc.execute("insert into data.log_level values (1,'info'),(2,'warning')");
        jdbc.execute("create table data.system_log(log_date timestamptz,log_level_id bigint,record_details text)");
    }
    @AfterEach void cleanup() {
        jdbc.execute("drop trigger if exists reject_row on data.patient_sex");
        jdbc.execute("drop function if exists data.reject_test_row()");
        jdbc.execute("delete from data.dsa_raw_direction_type");
        jdbc.execute("delete from data.dsa_raw_patient_sex");
        jdbc.execute("delete from data.direction_type");
        jdbc.execute("delete from data.patient_sex");
        jdbc.execute("delete from data.dsa_loaded_version");
        jdbc.execute("delete from data.dsa_load_batch");
        jdbc.execute("drop view access_work.users_v");
        jdbc.execute("drop table data.log_level");
        jdbc.execute("drop table data.system_log");
    }
    Path fixture(String name) throws Exception {
        return new org.springframework.core.io.ClassPathResource("fixtures/" + name + ".json").getFile().toPath();
    }
    DictionarySnapshot snapshot(String name) throws Exception {
        return JsonMapper.builder().build().readValue(fixture(name).toFile(),DictionarySnapshot.class);
    }
    @Test void routesTwoFilesThroughOneServiceAndKeepsDictionariesIsolated() throws Exception {
        jdbc.execute("insert into data.patient_sex(id,name,display_order,search_synonym) values (1,'Old',99,'Local'),(3,'Absent',null,null)");
        var direction = imports.loadFile(DIRECTION,fixture("direction-type"),7L).orElseThrow();
        var sex = imports.loadFile(SEX,fixture("patient-sex"),7L).orElseThrow();
        assertThat(direction.status()).isEqualTo("success");
        assertThat(sex.status()).isEqualTo("success");
        assertThat(direction.batchId()).isNotEqualTo(sex.batchId());
        assertThat(sex.entityName()).isEqualTo("patient_sex");
        assertThat(sex.rowsDeleted()).isEqualTo(1);
        assertThat(jdbc.queryForObject("select display_order from data.patient_sex where id=1",Integer.class)).isEqualTo(99);
        assertThat(jdbc.queryForObject("select search_synonym from data.patient_sex where id=1",String.class)).isEqualTo("Local");
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_raw_patient_sex where new_id=id",Integer.class)).isEqualTo(2);
        assertThat(imports.loadFile(SEX,fixture("patient-sex"),7L)).isEmpty();
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_load_batch",Integer.class)).isEqualTo(2);
    }
    @Test void rejectsWrongFileOidAndStaleSnapshotWithoutChangingRaw() throws Exception {
        assertThatThrownBy(() -> imports.loadFile(SEX,fixture("direction-type"),7L)).isInstanceOf(IllegalArgumentException.class);
        jdbc.execute("insert into data.dsa_loaded_version(entity_name,version) values ('patient_sex','3')");
        var s = snapshot("patient-sex");
        assertThatThrownBy(() -> apply.apply(s,7L,"https://example.test","1")).isInstanceOf(IllegalStateException.class);
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_raw_patient_sex",Integer.class)).isZero();
    }
    @Test void partialKeepsVersionAndAbsentRows() throws Exception {
        jdbc.execute("insert into data.patient_sex(id,name) values (3,'Absent')");
        jdbc.execute("insert into data.dsa_loaded_version(entity_name,version) values ('patient_sex','old')");
        jdbc.execute("CREATE FUNCTION data.reject_test_row() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF new.id=1 THEN RAISE EXCEPTION 'Rejected test row'; END IF; RETURN new; END $$");
        jdbc.execute("CREATE TRIGGER reject_row BEFORE INSERT ON data.patient_sex FOR EACH ROW EXECUTE FUNCTION data.reject_test_row()");
        var result = imports.loadFile(SEX,fixture("patient-sex"),7L).orElseThrow();
        assertThat(result.status()).isEqualTo("partial");
        assertThat(result.rowsRejected()).isEqualTo(1);
        assertThat(jdbc.queryForObject("select version from data.dsa_loaded_version where entity_name='patient_sex'",String.class)).isEqualTo("old");
        assertThat(jdbc.queryForObject("select is_deleted from data.patient_sex where id=3",String.class)).isEqualTo("N");
        assertThat(jdbc.queryForObject("select reject_reason from data.dsa_raw_patient_sex where id=1",String.class)).contains("Rejected");
    }
    @Test void lateSqlFailureRollsBackRawAcceptedVersionAndJournal() throws Exception {
        jdbc.execute("insert into data.dsa_raw_patient_sex(id,name) values (99,'Previous raw')");
        jdbc.execute("alter table data.system_log add constraint force_failure check (false)");
        var s = snapshot("patient-sex");
        assertThatThrownBy(() -> apply.apply(s,7L,"https://example.test",null)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(jdbc.queryForList("select id from data.dsa_raw_patient_sex",Long.class)).containsExactly(99L);
        assertThat(jdbc.queryForObject("select count(*) from data.patient_sex",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_loaded_version",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_load_batch",Integer.class)).isZero();
    }
    @Test void concurrentSameVersionCreatesOnlyOneBatch() throws Exception {
        var s = snapshot("patient-sex");
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            Callable<Boolean> task = () -> { start.await(); return apply.apply(s,7L,"https://example.test",null).isPresent(); };
            var a = executor.submit(task); var b = executor.submit(task);
            start.countDown();
            assertThat(java.util.List.of(a.get(20,TimeUnit.SECONDS),b.get(20,TimeUnit.SECONDS))).containsExactlyInAnyOrder(true,false);
        }
        assertThat(jdbc.queryForObject("select count(*) from data.dsa_load_batch",Integer.class)).isEqualTo(1);
    }
}
