
package com.example.app.batch.dto.output;

public record DictionarySyncDecisionDTO(
    String entityName,
    String currentVersion,
    String sourceVersion,
    boolean updateRequired,
    String reason
) {}
