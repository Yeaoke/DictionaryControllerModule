package com.example.app.integration.nsi.client;

import java.time.Duration;
import java.util.Arrays;
import java.util.Locale;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientRequestException;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import com.example.app.integration.nsi.dto.NsiDataPageResponse;
import com.example.app.integration.nsi.dto.NsiPassportResponse;
import com.example.app.integration.nsi.dto.NsiVersionsResponse;

import lombok.extern.log4j.Log4j2;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

@Log4j2
@Component
public class NsiMizdravClient {

    private static final String GET_DICTIONARIES_VERSIONS = "/rest/versions";

    private static final String GET_DICTIONARY_DATA = "/rest/data";
    
    private static final String GET_DICTIONARY_PASSPORT_STRUCTURE = "/rest/passport";

    private final WebClient webClient;
    private final String userKey;

    public NsiMizdravClient(
        @Qualifier("minzdravWebClient") WebClient webClient,
        @Value("${nsi.minzdrav.user-key}") String userKey
    ) {
        this.webClient = webClient;
        this.userKey = userKey;
    }

    public NsiPassportResponse getPassport(
        String oid
    ) {
        return executeRequest(
                webClient.get()
                    .uri(uriBuilder -> uriBuilder
                        .path(GET_DICTIONARY_PASSPORT_STRUCTURE)
                        .queryParam("identifier", oid)
                        .queryParam("userKey", userKey)
                        .build()
                    )
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .bodyToMono(NsiPassportResponse.class),
                    oid,
                    "passport"
                );
    }

    public NsiDataPageResponse getData(
        String oid,
        Integer page,
        Integer size,
        String sorting,
        String sortingDirection,
        String[] filters,
        String[] columns 
    ) {
        
        validateFilters(filters);

        validateColumns(columns);

        if (columns == null || columns.length <= 0) {
            throw new IllegalArgumentException(
                ""
            );
        }

        if (page != null && page < 0) {
            throw new IllegalArgumentException(
                "Номер страницы не должен быть отрицательным"
            );
        }

        if (size != null && size <= 0) {
            throw new IllegalArgumentException(
                "Размер страницы должен быть положительным"
            );
        }

        String direction = null;

        if (sortingDirection != null && !sortingDirection.isBlank()) {
            direction = sortingDirection.toUpperCase(Locale.ROOT);

            if (!direction.equals("ASC") && !direction.equals("DESC")) {
                throw new IllegalArgumentException(
                    "Направление сортировки должно быть ASC или DESC"
                );
            }
        }

        final String validatedDirection = direction;

        return executeRequest(
                webClient.get()
                    .uri(uriBuilder -> {
                            var builder = uriBuilder
                                .path(GET_DICTIONARY_DATA)
                                .queryParam("identifier", oid)
                                .queryParam("userKey", userKey);

                            if (page != null) {
                                builder.queryParam("page", page);
                            }

                            if (size != null) {
                                builder.queryParam("size", size);
                            }

                            if (sorting != null && !sorting.isBlank()) {
                                builder.queryParam("sorting", sorting);
                            }

                            if (sortingDirection != null && !sortingDirection.isBlank()) {
                                builder.queryParam("sortingDirection", validatedDirection);
                            }

                            if (filters != null && filters.length > 0) {
                                builder.queryParam("filters", Arrays.asList(filters));
                            }

                            if (columns != null && columns.length > 0) {
                                builder.queryParam("columns", Arrays.asList(columns));
                            }

                            return builder.build();
                        }
                    )
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .bodyToMono(NsiDataPageResponse.class),
                    oid,
                    "data"
                );
    }

    public NsiVersionsResponse getVersions(
        String oid,
        Integer page,
        Integer size
    ) {
        if (page != null && page < 0) {
            throw new IllegalArgumentException(
                "Номер страницы не должен быть отрицательным"
            );
        }

        if (size != null && size <= 0) {
            throw new IllegalArgumentException(
                "Размер страницы должен быть положительным"
            );
        }

        return executeRequest(
                webClient.get()
                    .uri(uriBuilder -> {
                        var builder = uriBuilder
                            .path(GET_DICTIONARIES_VERSIONS)
                            .queryParam("identifier", oid)
                            .queryParam("userKey", userKey);

                        if (page != null) {
                            builder.queryParam("page", page);
                        }

                        if (size != null) {
                            builder.queryParam("size", size);
                        }

                        return builder.build();
                        }
                    )
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .bodyToMono(NsiVersionsResponse.class),
                    oid,
                    "versions"
                );
    }

    private <T> T executeRequest(Mono<T> request, String oid, String operation) {
        return request
                    .switchIfEmpty(Mono.error(
                        new IllegalStateException(
                            "Пустой ответ API для OID: " + oid
                        )
                    ))
                    .retryWhen(
                        Retry.backoff(
                            2,
                            Duration.ofMillis(500)
                        )
                        .maxBackoff(Duration.ofSeconds(3))
                        .jitter(0.2)
                        .filter(this::isRetryable)
                        .doBeforeRetry(
                            signal -> log.warn(
                                "Повтор запроса {} OID: {}, попытка: {}", operation, oid, signal.totalRetries() + 2
                            )
                        )
                        .onRetryExhaustedThrow(
                            (spec, signal) -> signal.failure()
                        )
                    )
                    .timeout(Duration.ofSeconds(75))
                    .doOnSuccess(
                        result -> log.info(
                            "Запрос {} выполнен успешно для справочника OID: {}", operation, oid
                        )
                    )
                    .doOnError(
                        error -> log.error(
                            "Ошибка запроса {} для OID: {}", operation, oid, error
                        )
                    )
                    .block();
    }

    private boolean isRetryable(Throwable error) {

        if (error instanceof WebClientRequestException) {
            return true;
        }

        if (error instanceof WebClientResponseException ex) {
            return ex.getStatusCode().value() == 429 || ex.getStatusCode().is5xxServerError();
        }

        return false;
    }
    
    private void validateFilters(String[] filters) {
        if (filters == null) {
            return;
        }

        for (String filter : filters) {
            if (filter == null || filter.isBlank()) {
                throw new IllegalArgumentException(
                    "Фильтр не должен быть null или пустым"
                );
            }

            String[] parts = filter.split("\\|", -1);

            if (parts.length != 2 && parts.length != 3) {
                throw new IllegalArgumentException(
                    "Формат фильтра: FIELD|VALUE или FIELD|VALUE|TYPE"
                );
            }

            if (parts[0].isBlank()) {
                throw new IllegalArgumentException(
                    "В фильтре необходимо указать FIELD"
                );
            }

            if (parts.length == 3
                && !"EXACT".equals(parts[2])
                && !"LIKE".equals(parts[2])) {

                throw new IllegalArgumentException(
                    "TYPE должен быть EXACT или LIKE. "
                        + "Для поиска по умолчанию передай FIELD|VALUE"
                );
            }
        }
    }

    private void validateColumns(String[] columns) {
        if (columns == null) {
            return;
        }

        for (String column : columns) {
            if (column == null || column.isBlank()) {
                throw new IllegalArgumentException(
                    "Название столбца не должно быть null или пустым"
                );
            }
        }
    }
}
