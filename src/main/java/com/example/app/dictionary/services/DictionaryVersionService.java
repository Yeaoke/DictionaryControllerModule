package com.example.app.dictionary.services;

import org.springframework.stereotype.Service;

import com.example.app.dictionary.dto.DictionarySyncDecisionDTO;
import com.example.app.dictionary.dto.DictionaryVersionDTO;
import com.example.app.integration.nsi.services.NsiMzDictionaryService;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;

@Service
public class DictionaryVersionService {

    private static final String SAME_VERSIONS = "Версии одинаковые";
    private static final String NOT_LOADED = "Справочник ещё не загружен";
    private static final String DIFFERENT_VERSIONS = "Версии различаются";

    private final LoadedVersionJdbcRepository loadedVersionRepository;
    private final NsiMzDictionaryService nsiMzDictionaryService;

    public DictionaryVersionService(
        LoadedVersionJdbcRepository loadedVersionRepository,
        NsiMzDictionaryService nsiMzDictionaryService
    ) {
        this.loadedVersionRepository = loadedVersionRepository;
        this.nsiMzDictionaryService = nsiMzDictionaryService;
    }

    public DictionarySyncDecisionDTO checkDictionaryVersionForUpdate(
        String oid,
        String entityName
    ) {
        DictionaryVersionDTO mzDto = nsiMzDictionaryService.getCurrentVersion(oid);

        String sourceVersion = mzDto.version();

        if (sourceVersion == null || sourceVersion.isBlank()) {
            throw new IllegalStateException(
                "Минздрав не вернул версию справочника: " + oid
            );
        }

        String currentVersion = loadedVersionRepository
            .findVersionByEntityName(entityName)
            .orElse(null);

        if (currentVersion == null) {
            return new DictionarySyncDecisionDTO(
                entityName,
                null,
                sourceVersion,
                true,
                NOT_LOADED
            );
        }

        boolean updateRequired = !sourceVersion.equals(currentVersion);

        return new DictionarySyncDecisionDTO(
            entityName,
            currentVersion,
            sourceVersion,
            updateRequired,
            updateRequired ? DIFFERENT_VERSIONS : SAME_VERSIONS
        );
    }
}