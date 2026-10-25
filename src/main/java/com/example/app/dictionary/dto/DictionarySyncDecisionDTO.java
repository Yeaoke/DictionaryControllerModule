
package com.example.app.dictionary.dto;

public record DictionarySyncDecisionDTO(
    String entityName,
    String currentVersion,
    String sourceVersion,
    boolean updateRequired,
    String reason
) {}
