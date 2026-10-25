package com.example.app.loading.config;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("dictionaries")
public record DictionaryCatalog(
        List<Definition> definitions
) {
    public record Definition(
        String oid,
        String entityName,
        String stagingTable,
        String targetTable,
        String procedure,
        List<String> keyColumns,
        String sorting,
        List<Column> columns
    ) {}
    
    public record Column(
        String source,
        String target,
        ValueType type,
        boolean required,
        Integer maxLength,
        Integer precision,
        Integer scale
    ) {}
    public enum ValueType {
        LONG,
        INTEGER,
        STRING,
        DECIMAL,
        BOOLEAN,
        DATE,
        TIMESTAMP
    }
}
