package com.example.app.sync;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import java.time.LocalDateTime;
import static org.junit.jupiter.api.Assertions.*;

class SourceValuesTest {
    private final JsonMapper mapper = JsonMapper.builder().build();
    @Test void minimalSyncRequestUsesOptionalDefaults() {
        var request = mapper.readValue("{\"userId\":1}", SyncService.Request.class);
        assertEquals(1L, request.userId());
        assertNull(request.version());
        assertFalse(request.force());
        assertFalse(request.allowEmpty());
    }
    @Test void syncRequestSupportsNullAndExplicitFlags() {
        var defaults = mapper.readValue("{\"userId\":1,\"force\":null,\"allowEmpty\":null}", SyncService.Request.class);
        assertFalse(defaults.force());
        assertFalse(defaults.allowEmpty());
        var explicit = mapper.readValue("{\"userId\":1,\"force\":true,\"allowEmpty\":true}", SyncService.Request.class);
        assertTrue(explicit.force());
        assertTrue(explicit.allowEmpty());
    }
    @Test void strictNumbersAndBooleans() {
        assertEquals(9L,SourceValues.convert(mapper.readTree("\"9\""),"bigint"));
        assertThrows(ArithmeticException.class,()->SourceValues.convert(mapper.readTree("1.5"),"bigint"));
        assertThrows(ArithmeticException.class,()->SourceValues.convert(mapper.readTree("2147483648"),"integer"));
        assertThrows(ArithmeticException.class,()->SourceValues.convert(mapper.readTree("1.5"),"numeric(10)"));
        assertEquals(false,SourceValues.convert(mapper.readTree("\"0\""),"boolean"));
        assertThrows(IllegalArgumentException.class,()->SourceValues.convert(mapper.readTree("\"yes\""),"boolean"));
    }
    @Test void datesAreStrictAndOffsetIsNormalized() {
        assertEquals(LocalDateTime.of(2026,10,20,0,0),SourceValues.timestamp("20.10.2026"));
        assertEquals(LocalDateTime.of(2026,10,20,9,30),SourceValues.timestamp("2026-10-20T12:30:00+03:00"));
        assertThrows(IllegalArgumentException.class,()->SourceValues.timestamp("31.02.2026"));
    }
    @Test void retainsUnknownJsonAndRejectsDuplicateFields() {
        assertEquals("{\"extra\":true}",SourceValues.convert(mapper.readTree("{\"extra\":true}"),"text"));
        assertThrows(IllegalArgumentException.class,()->SourceValues.fields(mapper.readTree(
            "[{\"column\":\"ID\",\"value\":1},{\"column\":\"id\",\"value\":2}]")));
    }
    @Test void catalogCoversAll64TablesAndValidatesIdentifiers() throws Exception {
        var catalog = new DictionaryCatalog(mapper);
        assertEquals(64,catalog.all().size());
        assertEquals("1.2.643.5.1.13.13.11.1009",catalog.get("direction_type").oid());
        assertEquals(3,catalog.get("foms_payment_organization_details").keys().size());
        assertThrows(IllegalArgumentException.class,()->DictionaryCatalog.identifier("x;drop table y"));
    }
    @Test void stagingAliasesAreGenericAndDefaultToTarget() {
        var column=mapper.readValue("{\"target\":\"name\",\"type\":\"text\",\"source\":\"NAME\"}",
            DictionaryCatalog.Column.class);
        assertEquals("name",column.staging());
        var aliased=mapper.readValue("{\"target\":\"display_order\",\"type\":\"numeric(10)\",\"source\":\"SORT\",\"staging\":\"source_sort\"}",
            DictionaryCatalog.Column.class);
        assertEquals("source_sort",aliased.staging());
    }
}
