package com.example.app.dto.compare;

public record DictionaryVersionCompareDTO(
    String entityName,
    String firstVersion,
    String secondVersion,
    String newerVersion,
    String newerSource,
    ComparisonResult result
) {
    public enum ComparisonResult {
        FIRST_NEWER,
        SECOND_NEWER,
        EQUAL,
        NOT_FOUND,
        INCOMPARABLE
    }
}
