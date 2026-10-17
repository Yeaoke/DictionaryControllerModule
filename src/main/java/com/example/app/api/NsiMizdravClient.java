package com.example.app.api;


import java.time.Duration;

import org.springframework.http.MediaType;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientRequestException;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import com.example.app.dto.DictionaryVersionDTO;

import io.netty.channel.ChannelOption;
import lombok.extern.log4j.Log4j2;
import reactor.core.publisher.Mono;
import reactor.netty.http.client.HttpClient;
import reactor.util.retry.Retry;

@Log4j2
@Component
public class NsiMizdravClient {

    private final WebClient webClient;

    private HttpClient httpClient;

    public NsiMizdravClient(WebClient.Builder builder) {
        this.httpClient = HttpClient.create()
                            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 10000)
                            .responseTimeout(Duration.ofSeconds(15));

        this.webClient = builder
                            .clientConnector(new ReactorClientHttpConnector(httpClient))
                            .codecs(configurer -> configurer.defaultCodecs().maxInMemorySize(2 * 1024 * 1024))
                            .build();
    }

    public DictionaryVersionDTO makeRequestToGetDictionaryVersion(
        String oid,
        String apiURL
    ) {
        log.info("Запрос версии справочника OID: {}", oid);

        return webClient.get()
            .uri(urlConfigurer -> urlConfigurer
                                .scheme("https")
                                .host("nsi.minzdrav.ru")
                                .path(apiURL)
                                .queryParam("oid", oid)
                                .build())
            .accept(MediaType.APPLICATION_JSON)
            .retrieve()
            .bodyToMono(DictionaryVersionDTO.class)
            .switchIfEmpty(Mono.error(new IllegalArgumentException(
                "Пустой API для OID: " + oid    
            )))
            .retryWhen(
                Retry.backoff(2, Duration.ofMillis(500))
                .maxBackoff(Duration.ofSeconds(3))
                .jitter(0.2)
                .filter(this::isRetryable)
                .doBeforeRetry(
                    signal -> log.warn("Повтор запроса OID: {}, попытка: {}", oid, signal.totalRetries() + 2)
                )
                .onRetryExhaustedThrow((spec, signal) -> signal.failure())
            )

            .timeout(Duration.ofSeconds(75))

            .doOnSuccess(
                result -> log.info(
                    "Версия справочника OID: {} успешно получена", oid    
                )
            )

            .doOnError(
                error -> log.error(
                    "Версию спарвочника OID: {} не удалось получить", oid
                )
            )

            .block();
    }

    private boolean isRetryable(Throwable error) {
        
        if (error instanceof WebClientRequestException) {
            return true;
        }
        
        if (error instanceof WebClientResponseException ex) {
            int status = ex.getStatusCode().value();

            return status == 429 || ex.getStatusCode().is5xxServerError();
        }

        return false;
    }
}