package com.example.app.api.controllers;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.example.app.loading.dto.DictionaryLoadResultDTO;
import com.example.app.loading.services.DictionaryImportService;

@RestController
@RequestMapping("/api/dictionaries")
public class DictionaryImportController {

    private final DictionaryImportService importService;

    public DictionaryImportController(
        DictionaryImportService importService
    ) {
        this.importService = importService;
    }

    @PostMapping("/load")
    public ResponseEntity<ImportResponse> load(
        @RequestParam String oid,
        @RequestParam Long userId
    ) {
        var result = importService.load(oid, userId);

        if (result.isEmpty()) {
            return ResponseEntity.ok(
                new ImportResponse(
                    oid,
                    "skipped",
                    "Эта версия справочника уже загружена",
                    null
                )
            );
        }

        DictionaryLoadResultDTO batch = result.get();

        String message = switch (batch.status()) {
            case "success" -> "Справочник загружен";
            case "partial" -> "Загрузка выполнена частично";
            case "error" -> "Загрузка завершилась с ошибкой";
            default -> throw new IllegalStateException(
                "Неожиданный статус загрузки: " + batch.status()
            );
        };

        return ResponseEntity.ok(
            new ImportResponse(
                oid,
                batch.status(),
                message,
                batch
            )
        );
    }

    public record ImportResponse(
        String oid,
        String status,
        String message,
        DictionaryLoadResultDTO batch
    ) {}
}