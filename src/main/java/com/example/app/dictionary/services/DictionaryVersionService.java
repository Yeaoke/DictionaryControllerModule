package com.example.app.dictionary.services;

import org.springframework.stereotype.Service;

import com.example.app.dictionary.dto.DictionarySyncDecisionDTO;
import com.example.app.dictionary.dto.DictionaryVersionDTO;
import com.example.app.integration.nsi.services.NsiMzDictionaryService;
import com.example.app.loading.repos.DsaLoadedVersionRepository;

@Service
public class DictionaryVersionService {
    
    private final DsaLoadedVersionRepository dsaLoadedVersionRepository;
    private final NsiMzDictionaryService nsiMzDictionaryService;

    public DictionaryVersionService(
        DsaLoadedVersionRepository dsaLoadedVersionRepository,
        NsiMzDictionaryService nsiMzDictionaryService
    ) {
        this.dsaLoadedVersionRepository = dsaLoadedVersionRepository;
        this.nsiMzDictionaryService = nsiMzDictionaryService;
    }
    
    public DictionarySyncDecisionDTO checkDictionaryVersionForUpdate(String oid) {
        DictionaryVersionDTO mzDto = nsiMzDictionaryService.getCurrentVersion(oid);

        return new DictionarySyncDecisionDTO();
    }
}
