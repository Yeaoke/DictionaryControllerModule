package com.example.app.sync;

import java.time.Duration;
import org.springframework.beans.factory.annotation.*;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.*;
import reactor.util.retry.Retry;
import tools.jackson.databind.JsonNode;

@Component
public class NsiSourceClient {
    private final WebClient client;
    private final String key;
    public NsiSourceClient(
        @Qualifier("minzdravWebClient") WebClient client,
        @Value("${nsi.minzdrav.user-key:}") String key) {
            this.client = client;
            this.key = key;
    }
    public JsonNode passport(String oid, String version) {
        return request(
            "passport",
            oid, version,
            null,
            null
        );
    }
    public JsonNode page(
        String kind,
        String oid,
        String version,
        int page,
        int size
    ) {
        if (!kind.equals("data") && !kind.equals("versions")) {
            throw new IllegalArgumentException("Invalid page kind");
        }
        return request(
            kind,
            oid,
            version,
            page,
            size
        );
    }
    private JsonNode request(
        String operation,
        String oid,
        String version,
        Integer page,
        Integer size
    ) {
        if (key.isBlank()) throw new IllegalStateException("Задайте NSI_USER_KEY для загрузки НСИ");
        try {
            var result = client.get()
                .uri(b -> {
                    b.path("/rest/" + operation).queryParam("identifier", oid).queryParam("userKey", key);
                    if (version != null && !version.isBlank()) {
                        b.queryParam("version", version);
                    }
                    if (page != null) {
                        b.queryParam("page", page).queryParam("size", size);
                    }
                return b.build();
            })
            .retrieve()
            .bodyToMono(JsonNode.class)
                .retryWhen(Retry.backoff(2, Duration.ofMillis(500))
                    .filter(e -> e instanceof WebClientRequestException || e instanceof WebClientResponseException r && (r.getStatusCode().value() == 429 || r.getStatusCode().is5xxServerError()))
                    .onRetryExhaustedThrow((spec, signal) -> signal.failure()))
                .timeout(Duration.ofSeconds(90)).block();
            if (result == null || !"OK".equals(result.path("result").asText()))
                throw new IllegalStateException("НСИ вернул неуспешный ответ: " + operation);
            return result;
        } catch (WebClientResponseException e) {
            throw new IllegalStateException("НСИ HTTP " + e.getStatusCode().value() + ": " + operation);
        } catch (RuntimeException e) {
            if (e instanceof IllegalStateException && e.getMessage() != null && e.getMessage().startsWith("НСИ вернул")) throw e;
            throw new IllegalStateException("Ошибка связи/формата ответа НСИ: " + operation);
        }
    }
}
