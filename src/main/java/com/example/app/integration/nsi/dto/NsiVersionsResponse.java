package com.example.app.integration.nsi.dto;

import java.time.Instant;
import java.util.List;

public record NsiVersionsResponse(
    List<VersionItem> list,
    String result,
    String resultCode,
    String resultText,
    Integer total
) {
    public record VersionItem(
        Boolean archive,
        Instant createDate,
        Instant lastUpdate,
        Instant publishDate,
        String releaseNotes,
        String version
    ) {}
}