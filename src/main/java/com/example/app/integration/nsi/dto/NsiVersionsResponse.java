package com.example.app.integration.nsi.dto;

import java.time.LocalDateTime;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonFormat;

public record NsiVersionsResponse(
    List<VersionItem> list,
    String result,
    String resultCode,
    String resultText,
    Integer total
) implements NsiResponse {
    public record VersionItem(
        Boolean archive,
        @JsonFormat(pattern = "dd.MM.yyyy HH:mm")
        LocalDateTime createDate,
        @JsonFormat(pattern = "dd.MM.yyyy HH:mm")
        LocalDateTime lastUpdate,
        @JsonFormat(pattern = "dd.MM.yyyy HH:mm")
        LocalDateTime publishDate,
        String releaseNotes,
        String version
    ) {}
}
