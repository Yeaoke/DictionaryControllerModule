
package com.example.app.staging.model;

import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

import jakarta.persistence.*;

@Entity
@Table(
    name = "dsa_raw_direction_type",
    schema = "data"
)
@Getter
@Setter
@NoArgsConstructor
public class DsaRawDirectionType {

    @Id
    private Long id;

    @Column(
        name = "name",
        nullable = false,
        length = 100
    )
    private String name;

    @Column(
        name = "doc",
        length = 100
    )
    private String doc;

    @Column(
        name = "sort",
        precision = 10,
        scale = 0
    )
    private BigDecimal sort;

    @Column(
        name = "reject_reason",
        length = 100
    )
    private String rejectReason;

    @Column(name = "new_id")
    private Long newId;
}
