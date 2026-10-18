
package com.example.app.loading.models;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;

@Entity
@Table(
    name = "dsa_loaded_version",
    schema = "data"
)
@Getter
@Setter
@NoArgsConstructor
public class DsaLoadedVersion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(
        name = "entity_name",
        nullable = false,
        length = 100
    )
    private String entityName;
    
    @Column(
        name = "version",
        nullable = false,
        length = 100
    )
    private String version;
}
