package com.example.app.dictionary.services;

import java.util.Optional;

import org.springframework.stereotype.Service;

import com.example.app.dictionary.dto.DictionarySyncDecisionDTO;
import com.example.app.dictionary.dto.DictionaryVersionDTO;
import com.example.app.dictionary.source.DictionarySource;
import com.example.app.integration.nsi.services.NsiMzDictionaryService;
import com.example.app.loading.models.DsaLoadedVersion;
import com.example.app.loading.repos.DsaLoadedVersionRepository;

@Service
public class DictionaryVersionService {
    
    private static final String SAME_VERSIONS = "Версии одинаковые";
    private static final String NOT_FOUND_SOURCE_VERSION = "Нет данных об этом справочнике";
    private static final String DIFFERENT_VERSIONS = "Версии различаются";

    private final DsaLoadedVersionRepository dsaLoadedVersionRepository;
    private final NsiMzDictionaryService nsiMzDictionaryService;

    public DictionaryVersionService(
        DsaLoadedVersionRepository dsaLoadedVersionRepository,
        NsiMzDictionaryService nsiMzDictionaryService
    ) {
        this.dsaLoadedVersionRepository = dsaLoadedVersionRepository;
        this.nsiMzDictionaryService = nsiMzDictionaryService;
    }
    
    public DictionarySyncDecisionDTO checkDictionaryVersionForUpdate(String oid, String entityName) {
        DictionaryVersionDTO mzDto = nsiMzDictionaryService.getCurrentVersion(oid);

        Optional<DsaLoadedVersion> loadedVersion = dsaLoadedVersionRepository.findByEntityName(entityName, DictionarySource.FOMS.getCode());

        String mzVersion = mzDto.version();
        String currentVersion = loadedVersion.map(DsaLoadedVersion::getVersion).orElse(null);

        if (currentVersion == null) {
            return new DictionarySyncDecisionDTO(
                entityName,
                null,
                mzVersion,
                true,
                NOT_FOUND_SOURCE_VERSION
            );
        }

        if (mzVersion.equals(currentVersion)) {
            return new DictionarySyncDecisionDTO(
                entityName,
                currentVersion,
                mzVersion,
                false,
                SAME_VERSIONS
            );
        }

        return new DictionarySyncDecisionDTO(
                entityName,
                currentVersion,
                mzVersion,
                true,
                DIFFERENT_VERSIONS
            );
    }
}
