package com.example.app.sync;

import java.net.URI;
import java.net.http.*;
import java.util.*;
import java.util.stream.Collectors;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.JsonNode;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="TEST_DATABASE_URL", matches=".+")
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT, properties={
    "spring.datasource.url=${TEST_DATABASE_URL}",
    "spring.datasource.username=${TEST_DATABASE_USER:nsi_test}",
    "spring.datasource.password=${TEST_DATABASE_PASSWORD:}",
    "nsi.minzdrav.page-size=2"
})
class SyncIntegrationTest {
    @Autowired JdbcTemplate jdbc;
    @Autowired DictionaryCatalog catalog;
    @Autowired SyncStore store;
    @Autowired SyncService service;
    @Autowired DictionaryApplyService apply;
    @Autowired ObjectMapper mapper;
    @MockitoBean NsiSourceClient source;
    @Value("${local.server.port}") int port;

    @BeforeEach void cleanup() {
        jdbc.update("DELETE FROM data.nsi_sync_page");
        jdbc.update("DELETE FROM data.dsa_load_batch");
        jdbc.update("DELETE FROM data.nsi_dictionary_passport");
        jdbc.update("DELETE FROM data.nsi_dictionary_version");
        jdbc.update("DELETE FROM data.dsa_loaded_version");
        for (String name : List.of("direction_type","ambulance_call_order","foms_bill_type")) {
            jdbc.update("DELETE FROM data.dsa_raw_" + name);
            jdbc.update("DELETE FROM data." + name);
        }
        reset(source);
    }
    @Test void migrationsAndEntireCatalogMatchDatabase() {
        assertEquals(7,jdbc.queryForObject("SELECT count(*) FROM data.flyway_schema_history WHERE success AND version IS NOT NULL",Integer.class));
        for (var d:catalog.all()) {
            Set<String> target = new HashSet<>(jdbc.queryForList(
                "SELECT column_name FROM information_schema.columns WHERE table_schema='data' AND table_name=?",String.class,d.name()));
            Set<String> staging = new HashSet<>(jdbc.queryForList(
                "SELECT column_name FROM information_schema.columns WHERE table_schema='data' AND table_name=?",String.class,"dsa_raw_"+d.name()));
            for (var c:d.columns()) {
                assertTrue(target.contains(c.target()),d.name()+"."+c.target());
                String stage = c.staging();
                assertTrue(staging.contains(stage),d.name()+": staging "+stage);
            }
            Set<String> pk = new HashSet<>(jdbc.queryForList("""
                SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
                WHERE i.indrelid=to_regclass(?) AND i.indisprimary
                """,String.class,"data."+d.name()));
            assertEquals(pk,new HashSet<>(d.keys()),d.name());
        }
    }
    @Test void atomicUpsertSoftDeleteAndLocalFieldsPreserved() {
        var d=catalog.get("ambulance_call_order");
        UUID first=staged(d,"1", "[["+field("Id","1")+","+field("Name","\"first\"")+"],["+field("Id","2")+","+field("Name","\"second\"")+"]]");
        apply.apply(first,d,"1",2,false);
        jdbc.update("UPDATE data.ambulance_call_order SET search_synonym='local',display_order=77 WHERE id=1");
        UUID second=staged(d,"2","[["+field("Id","1")+","+field("Name","\"changed\"")+"]]");
        apply.apply(second,d,"2",1,false);
        var row=jdbc.queryForMap("SELECT * FROM data.ambulance_call_order WHERE id=1");
        assertEquals("local",row.get("search_synonym"));
        assertEquals("77",row.get("display_order").toString());
        assertEquals("changed",row.get("name"));
        assertEquals("Y",jdbc.queryForObject("SELECT is_deleted FROM data.ambulance_call_order WHERE id=2",String.class));
        assertEquals("2",store.loadedVersion(d.name()));
        assertEquals(1L,store.run(second).get("rows_deleted"));
        var batch = jdbc.queryForMap(
            "SELECT * FROM data.dsa_load_batch WHERE run_id=?", second);
        assertEquals("success", batch.get("status"));
        assertEquals("1", batch.get("current_version"));
        assertEquals("2", batch.get("rows_current").toString());
        assertEquals("2", batch.get("rows_new").toString());
        assertEquals("1", batch.get("rows_new_deleted").toString());
        assertEquals(batch.get("id"), store.run(second).get("batch_id"));
    }
    @Test void compositeKeysAndDateConversion() {
        var d=catalog.get("foms_bill_type");
        String values=field("billcod","\"01\"")+","+field("tf_okato","\"22\"")+","+field("bill_namp","\"name\"")
            +","+field("datebeg","\"20.10.2026\"")+","+field("IS_PAY","\"1\"");
        UUID id=staged(d,"1","[["+values+"]]");
        apply.apply(id,d,"1",1,false);
        assertEquals("01",jdbc.queryForObject("SELECT code FROM data.foms_bill_type",String.class));
        assertEquals(1,jdbc.queryForObject("SELECT count(*) FROM data.dsa_raw_foms_bill_type WHERE new_key IS NOT NULL",Integer.class));
    }
    @Test void everyDictionaryCanApplyAnEntireTypedRow() {
        for (var d:catalog.all()) {
            jdbc.update("DELETE FROM data.dsa_raw_"+d.name());
            jdbc.update("DELETE FROM data."+d.name());
            String fields=d.columns().stream().map(c -> field(c.source(),
                c.type().equals("timestamp without time zone") ? "\"2026-10-20\"" :
                c.type().equals("boolean") ? "true" :
                c.type().equals("text") || c.type().startsWith("varchar") ? "\"1\"" : "1"))
                .collect(Collectors.joining(","));
            UUID id=staged(d,"test-1","[["+fields+"]]");
            assertDoesNotThrow(()->apply.apply(id,d,"test-1",1,false),d.name());
            assertEquals(1,jdbc.queryForObject("SELECT count(*) FROM data."+d.name(),Integer.class),d.name());
        }
    }
    @Test void duplicateKeysAndEmptySnapshotCannotDamageCurrentData() {
        var d=catalog.get("ambulance_call_order");
        UUID seed=staged(d,"1","[["+field("Id","1")+","+field("Name","\"kept\"")+"]]");
        apply.apply(seed,d,"1",1,false);
        UUID bad=staged(d,"2","[["+field("Id","1")+","+field("Name","\"new\"")+"],["+field("Id","1")+","+field("Name","\"duplicate\"")+"]]");
        assertThrows(org.springframework.dao.DataAccessException.class,()->apply.apply(bad,d,"2",2,false));
        assertEquals("kept",jdbc.queryForObject("SELECT name FROM data.ambulance_call_order WHERE id=1",String.class));
        assertEquals("1",store.loadedVersion(d.name()));
        store.finish(bad,"failed","test");
        UUID empty=staged(d,"3","[]");
        assertThrows(IllegalArgumentException.class,()->apply.apply(empty,d,"3",0,false));
        assertEquals("N",jdbc.queryForObject("SELECT is_deleted FROM data.ambulance_call_order WHERE id=1",String.class));
    }
    @Test void syncLoadsEveryPageMetadataAndRawExtraFieldsThenSkipsSameVersion() throws Exception {
        var d=catalog.get("ambulance_call_order");
        JsonNode passport=passport(d,"2",3);
        when(source.passport(d.oid(),null)).thenReturn(passport);
        when(source.passport(d.oid(),"2")).thenReturn(passport);
        when(source.passport(d.oid(),"1")).thenReturn(passport(d,"1",1));
        when(source.page("versions",d.oid(),null,0,2)).thenReturn(mapper.readTree(
            "{\"list\":[{\"version\":\"1\",\"custom\":\"kept\"},{\"version\":\"2\"}],\"total\":2}"));
        when(source.page("data",d.oid(),"2",0,2)).thenReturn(mapper.readTree(
            "{\"list\":[["+field("Id","1")+","+field("Name","\"A\"")+","+field("EXTRA","{\"x\":true}")+"],["
            +field("Id","2")+","+field("Name","\"B\"")+"]]}"));
        when(source.page("data",d.oid(),"2",1,2)).thenReturn(mapper.readTree(
            "{\"list\":[["+field("Id","3")+","+field("Name","\"C\"")+"]]}"));
        UUID id=service.submit(d.name(),new SyncService.Request(5L,null,false,false));
        await(id,"success");
        assertEquals(3L,store.run(id).get("rows_received"));
        assertEquals(2,store.versions(d.name(),100,0).size());
        assertTrue(store.hasPassport(d.name(),"1"));
        assertTrue(store.page(id,"data",0).toString().contains("EXTRA"));
        UUID skipped=service.submit(d.name(),new SyncService.Request(5L,null,false,false));
        await(skipped,"skipped");
        verify(source,times(1)).page("data",d.oid(),"2",0,2);
        var response=HttpClient.newHttpClient().send(HttpRequest.newBuilder(
            URI.create("http://127.0.0.1:"+port+"/api/dictionaries/"+d.name()+"/rows?limit=2")).GET().build(),
            HttpResponse.BodyHandlers.ofString());
        assertEquals(200,response.statusCode());
        assertEquals(2,mapper.readTree(response.body()).size());
    }
    @Test void incompletePageLeavesTargetUntouchedAndRetainsFailedRun() throws Exception {
        var d=catalog.get("ambulance_call_order");
        jdbc.update("INSERT INTO data.ambulance_call_order(id,name) VALUES (1,'old')");
        when(source.passport(d.oid(),null)).thenReturn(passport(d,"2",3));
        when(source.page("versions",d.oid(),null,0,2)).thenReturn(mapper.readTree("{\"list\":[],\"total\":0}"));
        when(source.page("data",d.oid(),"2",0,2)).thenReturn(mapper.readTree("{\"list\":[]}"));
        UUID id=service.submit(d.name(),new SyncService.Request(5L,null,false,false));
        await(id,"failed");
        assertEquals("old",jdbc.queryForObject("SELECT name FROM data.ambulance_call_order WHERE id=1",String.class));
        assertTrue(store.page(id,"data",0).path("list").isEmpty());
        assertNull(store.loadedVersion(d.name()));
    }
    @Test void activeRunIsUniqueAndRecoveryReleasesSlot() {
        var d=catalog.get("ambulance_call_order");
        var request=new SyncService.Request(1L,null,false,false);
        UUID id=store.create(d,request);
        assertThrows(org.springframework.dao.DuplicateKeyException.class,()->store.create(d,request));
        service.recover(id);
        assertEquals("interrupted",store.run(id).get("status"));
        assertNotNull(store.create(d,request));
    }
    @Test void postAcceptsMinimalJsonAndExplainsInvalidBody() throws Exception {
        var d=catalog.get("direction_type");
        when(source.passport(d.oid(),null)).thenThrow(new IllegalStateException("Test source unavailable"));
        var client=HttpClient.newHttpClient();
        URI uri=URI.create("http://127.0.0.1:"+port+"/api/dictionaries/direction_type/sync");
        var response=client.send(HttpRequest.newBuilder(uri)
            .header("Content-Type","application/json")
            .POST(HttpRequest.BodyPublishers.ofString("{\"userId\":1}")).build(),
            HttpResponse.BodyHandlers.ofString());
        assertEquals(202,response.statusCode(),response.body());
        UUID id=UUID.fromString(mapper.readTree(response.body()).path("runId").asText());
        await(id,"failed");
        assertEquals(false,jdbc.queryForObject("SELECT force_reload FROM data.dsa_load_batch WHERE run_id=?",Boolean.class,id));
        assertEquals(false,jdbc.queryForObject("SELECT allow_empty FROM data.dsa_load_batch WHERE run_id=?",Boolean.class,id));
        var invalid=client.send(HttpRequest.newBuilder(uri)
            .header("Content-Type","application/json")
            .POST(HttpRequest.BodyPublishers.ofString("{}")).build(),
            HttpResponse.BodyHandlers.ofString());
        assertEquals(400,invalid.statusCode());
        assertTrue(mapper.readTree(invalid.body()).path("error").asText().contains("userId"));
    }
    @Test void recoveredRunCannotCommitItsOldSnapshot() {
        var d=catalog.get("ambulance_call_order");
        UUID id=staged(d,"old","[["+field("Id","1")+","+field("Name","\"stale\"")+"]]");
        service.recover(id);
        assertThrows(IllegalStateException.class,()->apply.apply(id,d,"old",1,false));
        assertEquals(0,jdbc.queryForObject("SELECT count(*) FROM data.ambulance_call_order",Integer.class));
    }
    @Test void genericLoaderUsesCatalogStagingAliasAndPreservesDocument() {
        var d=catalog.get("direction_type");
        String row=field("ID","10")+","+field("NAME","\"Direction\"")+","+field("DOC","\"Document\"")+","+field("SORT","42");
        UUID id=staged(d,"1","[["+row+"]]");
        apply.apply(id,d,"1",1,false);
        assertEquals("Document",jdbc.queryForObject("SELECT doc FROM data.direction_type WHERE id=10",String.class));
        assertEquals("42",jdbc.queryForObject("SELECT display_order::text FROM data.direction_type WHERE id=10",String.class));
        assertEquals("42",jdbc.queryForObject("SELECT sort::text FROM data.dsa_raw_direction_type WHERE id=10",String.class));
        assertEquals("success",store.run(id).get("status"));
    }
    private UUID staged(DictionaryCatalog.Definition d,String version,String rows) {
        UUID id=store.create(d,new SyncService.Request(1L,version,true,false));
        store.start(id);
        store.page(id,"data",0,mapper.readTree("{\"list\":"+rows+"}"));
        return id;
    }
    private String field(String column,String json) { return "{\"column\":\""+column+"\",\"value\":"+json+"}"; }
    private JsonNode passport(DictionaryCatalog.Definition d,String version,long rows) {
        String fields=d.columns().stream().map(c->"{\"field\":\""+c.source()+"\"}").collect(Collectors.joining(","));
        return mapper.readTree("{\"oid\":\""+d.oid()+"\",\"version\":\""+version+"\",\"rowsCount\":"+rows+",\"fields\":["+fields+"]}");
    }
    private void await(UUID id,String status) throws Exception {
        long until=System.nanoTime()+java.time.Duration.ofSeconds(15).toNanos();
        Map<String,Object> run;
        do {
            run=store.run(id);
            if (!Set.of("queued","running").contains(run.get("status"))) {
                assertEquals(status,run.get("status"),run.toString()); return;
            }
            Thread.sleep(30);
        } while(System.nanoTime()<until);
        fail("Timed out: "+run);
    }
}

