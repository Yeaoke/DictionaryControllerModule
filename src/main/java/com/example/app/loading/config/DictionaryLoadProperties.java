package com.example.app.loading.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

@ConfigurationProperties("dictionary.loading")
public record DictionaryLoadProperties(
    @DefaultValue("500") int pageSize,
    @DefaultValue("500") int jdbcBatchSize,
    @DefaultValue("2") int maxConcurrentImports
) {
    public DictionaryLoadProperties {
        if (pageSize < 1 || pageSize > 500 || jdbcBatchSize < 1 || jdbcBatchSize > 10000
                || maxConcurrentImports < 1 || maxConcurrentImports > 64) {
            throw new IllegalArgumentException("Invalid dictionary.loading limits: page-size 1..500, "
                + "jdbc-batch-size 1..10000, max-concurrent-imports 1..64");
        }
    }
    public static DictionaryLoadProperties defaults() {
        return new DictionaryLoadProperties(500, 500, 2);
    }
}
