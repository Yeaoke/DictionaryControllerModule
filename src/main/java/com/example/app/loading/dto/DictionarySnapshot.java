package com.example.app.loading.dto;

import java.util.List;
import java.util.Map;
import tools.jackson.databind.JsonNode;

public record DictionarySnapshot(
    String oid,
    String version,
    long total,
    List<Map<String, JsonNode>> rows
) {}
