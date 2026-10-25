package com.example.app.integration.nsi.dto;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonFormat;

public record NsiPassportResponse(

    @JsonFormat(pattern = "dd.MM.yyyy")
    LocalDate approveDate,
    Boolean archive,
    Long authOrganizationId,
    List<CodeItem> codes,
    @JsonFormat(pattern = "dd.MM.yyyy HH:mm")
    LocalDateTime createDate,
    String description,
    List<FieldItem> fields,
    String fullName,
    Long groupId,
    Boolean hierarchical,
    String identifier,
    List<KeyItem> keys,
    @JsonFormat(pattern = "dd.MM.yyyy HH:mm")
    LocalDateTime lastUpdate,
    List<LawItem> laws,
    Long nsiDictionaryId,
    String oid,
    @JsonFormat(pattern = "dd.MM.yyyy HH:mm")
    LocalDateTime publishDate,
    String releaseNotes,
    Long respOrganizationId,
    String result,
    String resultCode,
    String resultText,
    Long rowsCount,
    String shortName,
    String structureNotes,
    Long typeId,
    String version

) implements NsiResponse {

    public record CodeItem(
        String type,
        String value
    ) {}

    public record FieldItem(
        String alias,
        String dataType,
        String description,
        String field
    ) {}

    public record KeyItem(
        List<KeyComponent> components,
        String field,
        String name,
        Integer number,
        ReferenceItem reference,
        String type
    ) {}

    public record KeyComponent(
        String field,
        Integer number,
        String type
    ) {}

    public record ReferenceItem(
        String detailDisplayField,
        String detailField,
        Long detailVersionId,
        String masterField,
        Long masterVersionId
    ) {}

    public record LawItem(
        Long id,
        String version
    ) {}
}
