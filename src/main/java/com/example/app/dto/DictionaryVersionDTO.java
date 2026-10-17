package com.example.app.dto;

public record DictionaryVersionDTO(
    String oid,
    String name,
    String version,
    String source
) {}