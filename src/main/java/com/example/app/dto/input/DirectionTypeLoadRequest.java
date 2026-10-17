
package com.example.app.dto.input;

public record DirectionTypeLoadRequest(
    Long userId,
    String version,
    String dataSourceUrl
) {}
