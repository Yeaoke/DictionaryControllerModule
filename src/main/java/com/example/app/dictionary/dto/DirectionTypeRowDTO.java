package com.example.app.dictionary.dto;

public record DirectionTypeRowDTO(
    Long id,
    String name,
    String doc,
    Long sort,
    String rejectReason,
    Long newId
) {}
