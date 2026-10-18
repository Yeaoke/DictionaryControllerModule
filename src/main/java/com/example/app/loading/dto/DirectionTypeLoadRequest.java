
package com.example.app.loading.dto;

public record DirectionTypeLoadRequest(
    Long userId,
    String version,
    String dataSourceUrl
) {}
