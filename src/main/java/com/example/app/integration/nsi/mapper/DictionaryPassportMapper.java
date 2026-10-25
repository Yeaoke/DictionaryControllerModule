package com.example.app.integration.nsi.mapper;

import org.springframework.stereotype.Component;

import com.example.app.dictionary.dto.DictionaryVersionDTO;
import com.example.app.dictionary.source.DictionarySource;
import com.example.app.integration.nsi.dto.NsiPassportResponse;

@Component
public class DictionaryPassportMapper {
    
    public DictionaryVersionDTO toDtoMzData(
        NsiPassportResponse passport
    ) {
        if (passport == null || passport.oid() == null || passport.oid().isBlank()
                || passport.fullName() == null || passport.fullName().isBlank()
                || passport.version() == null || passport.version().isBlank()) {
            throw new IllegalArgumentException(
                "Справочник должен содержать определенные данные: oid, version, fullname"
            );
        }
        
        return new DictionaryVersionDTO(
            passport.oid(),
            passport.fullName(),
            passport.version(),
            DictionarySource.MZ.getCode()
        );
    }

}
