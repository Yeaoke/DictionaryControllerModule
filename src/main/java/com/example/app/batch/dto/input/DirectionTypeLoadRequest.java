
package com.example.app.batch.dto.input;

public record DirectionTypeLoadRequest(
    Long userId,
    String version,
    String dataSourceUrl
) {}
