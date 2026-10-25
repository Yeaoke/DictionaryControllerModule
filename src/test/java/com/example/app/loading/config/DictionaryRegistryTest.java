package com.example.app.loading.config;

import java.util.List;
import org.junit.jupiter.api.Test;
import static com.example.app.loading.config.DictionaryCatalog.*;
import static org.assertj.core.api.Assertions.*;

class DictionaryRegistryTest {
    @Test void blocksUnverifiedMappingButKeepsVerifiedDictionaryAvailable() {
        var verified = definition("1.2.3", "patient_sex", "ID");
        var unverified = definition("1.2.4", "other", "VERIFY_SOURCE_id");
        var registry = new DictionaryRegistry(new DictionaryCatalog(List.of(verified, unverified)));
        assertThat(registry.require("1.2.3")).isEqualTo(verified);
        assertThatThrownBy(() -> registry.require("1.2.4"))
            .isInstanceOf(IllegalStateException.class).hasMessageContaining("Unverified NSI column mapping");
    }

    private Definition definition(String oid, String entity, String source) {
        return new Definition(oid, entity, "data.dsa_raw_" + entity, "data." + entity,
            "dsa_data_load.load_" + entity, List.of("id"), source,
            List.of(new Column(source, "id", ValueType.LONG, true, null, null, null)));
    }
}
