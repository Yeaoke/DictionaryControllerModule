package com.example.app.loading;

import java.nio.file.Path;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import com.example.app.dictionary.services.DirectionTypeSyncService;
import lombok.extern.log4j.Log4j2;

/** Explicit opt-in; ordinary application startup never imports dictionaries. */
@Component
@Log4j2
@ConditionalOnProperty(name = "direction-type.import.enabled", havingValue = "true")
public class DirectionTypeImportRunner implements ApplicationRunner {
    private final DirectionTypeSyncService service;
    private final Long userId;
    private final String file;
    public DirectionTypeImportRunner(DirectionTypeSyncService service,
            @Value("${direction-type.import.user-id}") Long userId,
            @Value("${direction-type.import.file:}") String file) {
        this.service = service; this.userId = userId; this.file = file;
    }
    public void run(ApplicationArguments args) throws Exception {
        var result = file.isBlank() ? service.sync(userId) : service.loadFile(Path.of(file), userId);
        if (result.isEmpty()) { log.info("direction_type: version already loaded"); return; }
        var batch = result.get();
        log.info("direction_type: batch={}, status={}, inserted={}, updated={}, rejected={}",
            batch.batchId(), batch.status(), batch.rowsInserted(), batch.rowsUpdated(), batch.rowsRejected());
        // Apply transaction has already committed; failing the CLI preserves its journal.
        if (!"success".equals(batch.status()))
            throw new IllegalStateException("Load batch " + batch.batchId() + ": " + batch.status() + ": " + batch.errorMessage());
    }
}
