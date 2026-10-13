package com.example.app.batch.dto.output;

import java.time.OffsetDateTime;

public record DirectionTypeLoadResultDTO(
    Long batchId,
    String entityName,
    String dataSource,
    String currentVersion,
    String newVersion,
    String status,
    OffsetDateTime startedAt,
    OffsetDateTime finishedAt,
    Long rowsCurrent,
    Long rowsCurrentDeleted,
    Long rowsExtracted,
    Long rowsRejected,
    Long rowsInserted,
    Long rowsUpdated,
    Long rowsDeleted,
    Long rowsNew,
    Long rowsNewDeleted,
    String errorMessage
) {}
