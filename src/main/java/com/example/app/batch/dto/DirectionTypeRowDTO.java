package com.example.app.batch.dto;

public record DirectionTypeRowDTO(
    Long id,
    String name,
    String doc,
    Long sort,
    String rejectReason,
    Long newId
) {}
