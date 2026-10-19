package com.example.app.integration.nsi.services;

import org.springframework.stereotype.Service;

import com.example.app.dictionary.dto.DictionaryVersionDTO;
import com.example.app.integration.nsi.client.NsiMizdravClient;
import com.example.app.integration.nsi.dto.NsiPassportResponse;
import com.example.app.integration.nsi.exceptions.APIError;
import com.example.app.integration.nsi.mapper.DictionaryPassportMapper;

@Service
public class NsiMzDictionaryService {
    
    private final NsiMizdravClient client;
    private final DictionaryPassportMapper versionMapper;

    public NsiMzDictionaryService(NsiMizdravClient client, DictionaryPassportMapper versionMapper) {
        this.client = client;
        this.versionMapper = versionMapper;
    }

    public DictionaryVersionDTO getCurrentVersion(String oid) {
        NsiPassportResponse passport = client.getPassport(oid);

        if (!passport.result().equals("OK")) {
            throw new APIError(
                "API request failed with code - " + passport.result()
            );
        }

        DictionaryVersionDTO result = versionMapper.toDtoMzData(passport);

        if (!oid.equals(result.oid())) {
            throw new IllegalStateException(
                "Минздрав вернул паспорт другого справочника"
            );
        }

        return result;
    }
}