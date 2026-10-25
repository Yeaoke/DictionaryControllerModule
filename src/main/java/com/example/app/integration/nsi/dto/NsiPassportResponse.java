package com.example.app.integration.nsi.dto;

import java.time.Instant;
import java.util.List;

public record NsiPassportResponse(

    Instant approveDate,
    Boolean archive,
    Long authOrganizationId,
    List<CodeItem> codes,
    Instant createDate,
    String description,
    List<FieldItem> fields,
    String fullName,
    Long groupId,
    Boolean hierarchical,
    String identifier,
    List<KeyItem> keys,
    Instant lastUpdate,
    List<LawItem> laws,
    Long nsiDictionaryId,
    String oid,
    Instant publishDate,
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
