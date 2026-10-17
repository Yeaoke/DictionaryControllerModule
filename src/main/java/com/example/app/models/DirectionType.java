
package com.example.app.models;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Entity
@Table(
    name = "direction_type",
    schema = "data"
)
@Getter
@Setter
@NoArgsConstructor
public class DirectionType {

    @Id
    @Column(name = "id")
    private Long id;

    @Column(
        name = "name",
        nullable = false,
        length = 200
    )
    private String name;

    @Column(
        name = "is_deleted",
        nullable = false,
        length = 1,
        columnDefinition = "char(1)"
    )
    private String isDeleted = "N";

    @Column(
        name = "display_order",
        precision = 10,
        scale = 0
    )
    private BigDecimal displayOrder;

    @Column(
        name = "search_synonym",
        length = 100
    )
    private String searchSynonym;
}
