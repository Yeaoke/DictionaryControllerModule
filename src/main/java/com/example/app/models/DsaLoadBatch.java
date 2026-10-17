
package com.example.app.models;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(
    name = "dsa_load_batch",
    schema = "data"
)
@Getter
@Setter
@NoArgsConstructor
public class DsaLoadBatch {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(
        name = "data_source",
        nullable = false,
        length = 10
    )
    private String dataSource;

    @Column(
        name = "data_source_url",
        nullable = false,
        length = 500
    )
    private String dataSourceUrl;

    @Column(
        name = "entity_name",
        nullable = false,
        length = 100
    )
    private String entityName;

    @Column(
        name = "dsa_table_name",
        nullable = false,
        length = 100
    )
    private String dsaTableName;

    @Column(
        name = "data_table_name",
        nullable = false,
        length = 100
    )
    private String dataTableName;

    @Column(
        name = "load_type",
        nullable = false,
        length = 20
    )
    private String loadType;
    @Column(
        name = "load_procedure_name",
        nullable = false,
        length = 100
    )
    private String loadProcedureName;

    @Column(
        name = "current_version",
        length = 100
    )
    private String currentVersion;

    @Column(
        name = "new_version",
        length = 100
    )
    private String newVersion;

    @Column(
        name = "started_at",
        nullable = false,
        insertable = false,
        updatable = false
    )
    private OffsetDateTime startedAt;

    @Column(name = "finished_at")
    private OffsetDateTime finishedAt;

    @Column(
        name = "loaded_by",
        length = 100
    )
    private String loadedBy;

    @Column(
        name = "status",
        nullable = false,
        length = 10
    )
    private String status;

    @Column(
        name = "rows_current",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsCurrent;

    @Column(
        name = "rows_current_deleted",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsCurrentDeleted;

    @Column(
        name = "rows_extracted",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsExtracted;

    @Column(
        name = "rows_rejected",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsRejected;

    @Column(
        name = "rows_inserted",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsInserted;

    @Column(
        name = "rows_updated",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsUpdated;

    @Column(
        name = "rows_deleted",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsDeleted;

    @Column(
        name = "rows_new",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsNew;

    @Column(
        name = "rows_new_deleted",
        precision = 10,
        scale = 0
    )
    private BigDecimal rowsNewDeleted;

    @Column(
        name = "error_message",
        length = 1000
    )
    private String errorMessage;
}
