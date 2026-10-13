
package com.example.app.batch.dto;

public record DictionaryVersionDTO(
    String entityName,
    String version,
    String dataSource,
    String dataSourceUrl
) {}
