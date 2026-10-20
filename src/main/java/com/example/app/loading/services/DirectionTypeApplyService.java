package com.example.app.loading.services;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.app.dictionary.dto.DirectionTypeRowDTO;
import com.example.app.loading.dto.DirectionTypeLoadResultDTO;
import com.example.app.staging.repos.DirectionTypeStagingJdbcRepository;

@Service
public class DirectionTypeApplyService {

    private final DirectionTypeStagingJdbcRepository stagingRepository;
    private final DirectionTypeLoadService directionTypeLoadService;

    public DirectionTypeApplyService(
        DirectionTypeStagingJdbcRepository stagingRepository,
        DirectionTypeLoadService directionTypeLoadService
    ) {
        this.stagingRepository = stagingRepository;
        this.directionTypeLoadService = directionTypeLoadService;
    }

    @Transactional
    public DirectionTypeLoadResultDTO apply(
        List<DirectionTypeRowDTO> rows,
        Long userId,
        String version,
        String sourceUrl
    ) {
        if (userId == null) {
            throw new IllegalArgumentException("userId обязателен");
        }

        if (version == null || version.isBlank() || version.length() > 100) {
            throw new IllegalArgumentException(
                "Версия обязательна и не должна превышать 100 символов"
            );
        }

        if (sourceUrl == null || sourceUrl.isBlank() || sourceUrl.length() > 500) {
            throw new IllegalArgumentException(
                "URL источника обязателен и не должен превышать 500 символов"
            );
        }

        

        stagingRepository.replaceAll(rows);
        return directionTypeLoadService.loadDirectionType(userId, version, sourceUrl);
    }
}