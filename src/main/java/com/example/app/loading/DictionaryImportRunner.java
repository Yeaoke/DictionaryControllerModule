package com.example.app.loading;

import java.nio.file.Path;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import com.example.app.loading.services.DictionaryImportService;
import lombok.extern.log4j.Log4j2;

/** Explicit opt-in; ordinary application startup never imports dictionaries. */
@Component
@org.springframework.core.annotation.Order(100)
@Log4j2
@ConditionalOnProperty(name = "dictionary.import.enabled", havingValue = "true")
public class DictionaryImportRunner implements ApplicationRunner {
    
    private final DictionaryImportService service;
    private final Long userId;
    private final String file;
    private final String oid;
    
    public DictionaryImportRunner(
        DictionaryImportService service,
        @Value("${dictionary.import.user-id}") Long userId,
        @Value("${dictionary.import.file:}") String file,
        @Value("${dictionary.import.oid}") String oid
    ) {
        this.service = service;
        this.userId = userId;
        this.file = file;
        this.oid = oid;
    }
    public void run(ApplicationArguments args) throws Exception {
        var result = file.isBlank() ? service.load(oid, userId) : service.loadFile(oid, Path.of(file), userId);
        if (result.isEmpty()) {
            log.info("Dictionary: version already loaded"); 
            return;
        }

        var batch = result.get();
        log.info("Dictionary: batch={}, status={}, inserted={}, updated={}, rejected={}",
            batch.batchId(), batch.status(), batch.rowsInserted(), batch.rowsUpdated(), batch.rowsRejected());
        
            if (!"success".equals(batch.status())) {
            throw new IllegalStateException("Load batch " + batch.batchId() + ": " + batch.status() + ": " + batch.errorMessage());
        }
    }
}
