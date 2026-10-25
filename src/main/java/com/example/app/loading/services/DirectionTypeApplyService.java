package com.example.app.loading.services;

import java.util.Objects;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.example.app.loading.dto.DirectionTypeSnapshot;
import com.example.app.loading.dto.DirectionTypeLoadResultDTO;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;
import com.example.app.staging.repos.DirectionTypeStagingJdbcRepository;

@Service
public class DirectionTypeApplyService {
    private final JdbcTemplate jdbc;
    private final LoadedVersionJdbcRepository versions;
    private final DirectionTypeStagingJdbcRepository staging;
    private final DirectionTypeLoadService loader;
    public DirectionTypeApplyService(JdbcTemplate jdbc, LoadedVersionJdbcRepository versions,
            DirectionTypeStagingJdbcRepository staging, DirectionTypeLoadService loader) {
        this.jdbc = jdbc; this.versions = versions; this.staging = staging; this.loader = loader;
    }
    @Transactional
    public Optional<DirectionTypeLoadResultDTO> apply(DirectionTypeSnapshot snapshot, Long userId,
            String sourceUrl, String expectedCurrentVersion) {
        Objects.requireNonNull(snapshot, "snapshot");
        if (userId == null || sourceUrl == null || sourceUrl.isBlank() || sourceUrl.length() > 500)
            throw new IllegalArgumentException("userId and sourceUrl (max 500) required");
        jdbc.execute("DO $$ BEGIN PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.direction_type', 0)); END $$");
        String current = versions.findVersionByEntityName("direction_type").orElse(null);
        if (snapshot.version().equals(current)) return Optional.empty();
        if (!Objects.equals(current, expectedCurrentVersion))
            throw new IllegalStateException("Loaded version changed during download; restart synchronization");
        staging.replaceAll(snapshot);
        return Optional.of(loader.loadDirectionType(userId, snapshot.version(), sourceUrl));
    }
}
