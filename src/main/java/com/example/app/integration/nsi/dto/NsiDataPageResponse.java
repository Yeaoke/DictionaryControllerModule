package com.example.app.integration.nsi.dto;

import java.util.List;
import tools.jackson.databind.JsonNode;

public record NsiDataPageResponse(
    List<List<DataItem>> list,
    String result,
    String resultCode,
    String resultText,
    Integer total
) {
    public record DataItem(
        String column,
        JsonNode value
    ) {}
}