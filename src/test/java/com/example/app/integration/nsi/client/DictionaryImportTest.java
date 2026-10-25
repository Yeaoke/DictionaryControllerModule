package com.example.app.integration.nsi.client;

import java.util.*;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import com.example.app.loading.config.*;
import com.example.app.loading.config.DictionaryCatalog.*;
import com.example.app.loading.dto.DictionarySnapshot;
import com.example.app.loading.services.*;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;
import com.example.app.integration.nsi.dto.*;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.*;

class DictionaryImportTest {
    static final String OID = "1.2.3";
    static Definition definition() {
        return new Definition(OID,"test_dictionary","data.dsa_raw_test_dictionary","data.test_dictionary",
            "dsa_data_load.load_test_dictionary",List.of("id"),"ID",List.of(
                new Column("ID","id",ValueType.LONG,true,null,null,null),
                new Column("NAME","name",ValueType.STRING,true,10,null,null)));
    }
    final JsonMapper json = JsonMapper.builder().build();
    final DictionaryRegistry registry = new DictionaryRegistry(new DictionaryCatalog(List.of(definition())));
    final NsiMizdravClient client = mock(NsiMizdravClient.class);
    final DictionaryApplyService apply = mock(DictionaryApplyService.class);
    final LoadedVersionJdbcRepository versions = mock(LoadedVersionJdbcRepository.class);
    final DictionaryImportService service = new DictionaryImportService(registry, mock(DictionarySchemaValidator.class),
        client, versions, apply, "https://example.test/port");
    NsiPassportResponse passport(String version, int count) {
        return json.readValue("{\"oid\":\"1.2.3\",\"version\":\"" + version + "\",\"rowsCount\":" + count + "}", NsiPassportResponse.class);
    }
    NsiDataPageResponse page(int id, int total) {
        return json.readValue("{\"total\":" + total + ",\"result\":\"OK\",\"list\":[[{\"column\":\"ID\",\"value\":" + id
            + "},{\"column\":\"NAME\",\"value\":\"Test\"}]]}", NsiDataPageResponse.class);
    }
    void prepare() { when(client.getPassport(OID)).thenReturn(passport("2",2)); }
    @Test void dispatchesCompleteSnapshotByOid() {
        prepare();
        when(client.getData(OID,"2",1,500,"ID","ASC")).thenReturn(page(1,2));
        when(client.getData(OID,"2",2,500,"ID","ASC")).thenReturn(page(2,2));
        service.load(OID,7L);
        verify(apply).apply(argThat(s -> s.oid().equals(OID) && s.rows().size()==2), eq(7L), anyString(), isNull());
    }
    @Test void duplicatePageAndMissingPageDoNotApply() {
        prepare();
        when(client.getData(OID,"2",1,500,"ID","ASC")).thenReturn(page(1,2));
        when(client.getData(OID,"2",2,500,"ID","ASC")).thenReturn(page(1,2));
        assertThatThrownBy(() -> service.load(OID,7L)).isInstanceOf(IllegalStateException.class);
        when(client.getData(OID,"2",2,500,"ID","ASC")).thenReturn(null);
        assertThatThrownBy(() -> service.load(OID,7L)).isInstanceOf(IllegalStateException.class);
        verifyNoInteractions(apply);
    }
    @Test void changedPassportDoesNotApply() {
        when(client.getPassport(OID)).thenReturn(passport("2",1),passport("3",1));
        when(client.getData(OID,"2",1,500,"ID","ASC")).thenReturn(page(1,1));
        assertThatThrownBy(() -> service.load(OID,7L)).isInstanceOf(IllegalStateException.class);
        verifyNoInteractions(apply);
    }
    @Test void unknownOidNeverCallsNetwork() {
        assertThatThrownBy(() -> service.load("unknown",7L)).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(client,apply);
    }
    @Test void rejectsDuplicateDefinitionsAndSqlIdentifiers() {
        assertThatThrownBy(() -> new DictionaryRegistry(new DictionaryCatalog(List.of(definition(),definition()))))
            .isInstanceOf(IllegalArgumentException.class);
        var d = definition();
        var bad = new Definition(d.oid(),"test;drop table data.direction_type",d.stagingTable(),d.targetTable(),d.procedure(),d.keyColumns(),d.sorting(),d.columns());
        assertThatThrownBy(() -> new DictionaryRegistry(new DictionaryCatalog(List.of(bad)))).isInstanceOf(IllegalArgumentException.class);
    }
    DictionarySnapshot snapshot(String rows, int total) {
        return json.readValue("{\"oid\":\"1.2.3\",\"version\":\"2\",\"total\":"+total+",\"rows\":"+rows+"}",DictionarySnapshot.class);
    }
    @Test void mapperPreservesTextAndRejectsInvalidRows() {
        var mapper = new DictionaryRowMapper();
        assertThat(mapper.map(definition(),snapshot("[{\"ID\":1,\"NAME\":\"O'Reilly\"}]",1)).getFirst())
            .containsExactly(1L,"O'Reilly");
        for (String rows : List.of("[{\"ID\":1.2,\"NAME\":\"A\"}]", "[{\"ID\":1,\"NAME\":\"\"}]",
                "[{\"ID\":1}]", "[{\"ID\":1,\"NAME\":\"12345678901\"}]"))
            assertThatThrownBy(() -> mapper.map(definition(),snapshot(rows,1))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> mapper.map(definition(),snapshot("[]",0))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> mapper.map(definition(),snapshot("[{\"ID\":1,\"NAME\":\"A\"},{\"ID\":\"1\",\"NAME\":\"B\"}]",2)))
            .isInstanceOf(IllegalArgumentException.class);
    }
}
