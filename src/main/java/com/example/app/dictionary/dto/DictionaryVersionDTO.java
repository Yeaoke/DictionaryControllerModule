package com.example.app.dictionary.dto;

public record DictionaryVersionDTO(
    String oid,
    String name,
    String version,
    String source
) {}