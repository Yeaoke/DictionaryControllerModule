package com.example.app.integration.nsi.services;

import org.springframework.stereotype.Service;

import com.example.app.dictionary.dto.DictionaryVersionDTO;
import com.example.app.integration.nsi.client.NsiMizdravClient;
import com.example.app.integration.nsi.dto.NsiPassportResponse;
import com.example.app.integration.nsi.mapper.DictionaryPassportMapper;

@Service
public class NsiDictionaryMzService {
    
    private final NsiMizdravClient client;
    private final DictionaryPassportMapper versionMapper;

    public NsiDictionaryMzService(NsiMizdravClient client, DictionaryPassportMapper versionMapper) {
        this.client = client;
        this.versionMapper = versionMapper;
    }

    public DictionaryVersionDTO getCurrentVersion(String oid) {
        NsiPassportResponse passport = client.getPassport(oid);

        return versionMapper.toDtoMzData(passport);
    }

}