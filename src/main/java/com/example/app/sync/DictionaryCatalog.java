package com.example.app.sync;

import java.io.IOException;
import java.util.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

@Component
public class DictionaryCatalog {
    public record Column(String target, String type, String source, String staging) {
        public Column {
            staging = staging == null ? target : staging;
        }
    }
    public record Definition(String name, String oid, List<String> keys, List<Column> columns) {}
    private final Map<String, Definition> definitions = new LinkedHashMap<>();

    public DictionaryCatalog(ObjectMapper mapper) throws IOException {
        try (var input = new ClassPathResource("dictionary-catalog.json").getInputStream()) {
            for (var d : mapper.readValue(input, Definition[].class)) {
                identifier(d.name());
                if (!d.oid().matches("[0-9]+(\\.[0-9]+)+") || d.keys().isEmpty())
                    throw new IllegalArgumentException("Invalid catalog entry: " + d.name());
                var targets = new HashSet<String>();
                var stagingColumns = new HashSet<String>();
                for (var c : d.columns()) {
                    identifier(c.target());
                    identifier(c.staging());
                    if (!targets.add(c.target()) || !stagingColumns.add(c.staging()) || c.source().isBlank())
                        throw new IllegalArgumentException("Invalid column: " + d.name());
                }
                if (!targets.containsAll(d.keys()) || definitions.put(d.name(), d) != null)
                    throw new IllegalArgumentException("Invalid keys/duplicate: " + d.name());
            }
        }
    }
    public Collection<Definition> all() { return Collections.unmodifiableCollection(definitions.values()); }
    public Definition get(String name) {
        var d = definitions.get(name);
        if (d == null) throw new NoSuchElementException("Неизвестный справочник: " + name);
        return d;
    }
    public static String identifier(String value) {
        if (!value.matches("[a-z][a-z0-9_]*")) throw new IllegalArgumentException("Invalid SQL identifier");
        return "\"" + value + "\"";
    }
}
