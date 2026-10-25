package com.example.app.loading.config;

import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import com.example.app.loading.config.DictionaryCatalog.*;

@Component
@EnableConfigurationProperties(DictionaryCatalog.class)
public class DictionaryRegistry {
    
    private final Map<String, Definition> definitions;
    
    public DictionaryRegistry(
        DictionaryCatalog catalog
    ) {
        if (catalog.definitions() == null || catalog.definitions().isEmpty()) {
            throw new IllegalArgumentException("Dictionary catalog is empty");
        }
        
        var map = new HashMap<String, Definition>();
        
        var entities = new HashSet<String>();
        
        for (var d : catalog.definitions()) {
            if (d.oid() == null || !d.oid().matches("[0-9]+(\\.[0-9]+)+")) {
                fail("Invalid OID");
            }

            identifier(d.entityName());
            if (!Objects.equals(d.stagingTable(), "data.dsa_raw_" + d.entityName()) || !Objects.equals(d.targetTable(), "data." + d.entityName()) || !Objects.equals(d.procedure(), "dsa_data_load.load_" + d.entityName())) {
                fail("Tables/procedure must match entity " + d.entityName());
            }
            
            if (d.columns() == null || d.columns().isEmpty() || d.keyColumns() == null || d.keyColumns().isEmpty()) {
                fail("Columns and keys are required");
            }
            
            var targets = new HashSet<String>();
            
            var sources = new HashSet<String>();
            
            for (var c : d.columns()) {
                identifier(c.target());
                
                if (Set.of("raw_row_id", "reject_reason", "new_id", "new_key", "is_deleted", "search_synonym").contains(c.target())) {
                    fail("Reserved input column: " + c.target());
                }
                if (c.source() == null || c.source().isBlank() || c.type() == null || !sources.add(c.source()) || !targets.add(c.target())) {
                    fail("Invalid/duplicate column");
                }
                if (c.maxLength() != null && c.maxLength() < 1) {
                    fail("Invalid maxLength");
                }
                if (c.precision() != null && (c.precision() < 1 || c.scale() == null || c.scale() < 0 || c.scale() > c.precision())) {
                    fail("Invalid decimal precision/scale");
                }
            }
            
            if (new HashSet<>(d.keyColumns()).size() != d.keyColumns().size() || !targets.containsAll(d.keyColumns())) {
                fail("Invalid key columns");
            }            
            if (d.sorting() == null || !sources.contains(d.sorting())) {
                fail("Sorting must be a source column");
            }
            if (map.putIfAbsent(d.oid(), d) != null || !entities.add(d.entityName())) {
                fail("Duplicate OID/entity");
            }
        }
        definitions = Map.copyOf(map);
    }

    public Definition require(String oid) {
        if (oid == null || !definitions.containsKey(oid)) {
            throw new IllegalArgumentException("Unsupported dictionary OID: " + oid);
        
        }
        return definitions.get(oid);
    }

    public Collection<Definition> all() {
        return definitions.values();
    }
    
    private static void identifier(String value) {
        if (value == null || !value.matches("[a-z][a-z0-9_]{0,62}")) {
            fail("Unsafe SQL identifier");
        }
    }

    private static void fail(
        String message
    ) {
        throw new IllegalArgumentException(message);
    }
}
