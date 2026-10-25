package com.example.app.integration.nsi.client;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.ClientRequest;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import com.example.app.integration.nsi.exceptions.APIError;

import reactor.core.publisher.Mono;

import static org.assertj.core.api.Assertions.*;

class NsiMizdravClientTest {
    @Test
    void pinsVersionAndPreservesBasePath() {
        var api = client(200, "{\"result\":\"OK\",\"list\":[],\"total\":0}");
        api.getData("1.2.3", "2.5", 1, 500, "ID", "ASC");
        assertThat(captured.get().url().getQuery()).contains("version=2.5", "page=1");
    }
    private final AtomicInteger calls = new AtomicInteger();
    private final AtomicReference<ClientRequest> captured = new AtomicReference<>();

    private NsiMizdravClient client(int status, String body) {
        WebClient webClient = WebClient.builder().baseUrl("https://example.test")
            .exchangeFunction(request -> {
                captured.set(request);
                return Mono.defer(() -> {
                    calls.incrementAndGet();
                    var response = ClientResponse.create(HttpStatus.valueOf(status))
                        .header("Content-Type", MediaType.APPLICATION_JSON_VALUE);
                    if (!body.isEmpty()) response.body(body);
                    return Mono.just(response.build());
                });
            }).build();
        return new NsiMizdravClient(webClient, "test-key");
    }

    private Object invoke(NsiMizdravClient client, String operation) {
        return switch (operation) {
            case "passport" -> client.getPassport("1.2.3");
            case "data" -> client.getData("1.2.3", 0, 10, "ID", "asc");
            case "versions" -> client.getVersions("1.2.3", 0, 10);
            default -> throw new IllegalArgumentException(operation);
        };
    }

    @ParameterizedTest
    @ValueSource(strings = {"passport", "data", "versions"})
    void rejectsBusinessErrorsWithoutRetry(String operation) {
        var client = client(200, """
            {"result":"ERROR","resultCode":"ACCESS_DENIED","resultText":"Access denied"}
            """);
        assertThatThrownBy(() -> invoke(client, operation))
            .isInstanceOfSatisfying(APIError.class, error -> {
                assertThat(error.getResultCode()).isEqualTo("ACCESS_DENIED");
                assertThat(error.getResultText()).isEqualTo("Access denied");
                assertThat(error.getMessage()).contains(operation, "1.2.3", "ACCESS_DENIED");
            });
        assertThat(calls.get()).isEqualTo(1);
    }

    @ParameterizedTest
    @ValueSource(strings = {"passport", "data", "versions"})
    void rejectsMissingStatusWithoutNullPointerException(String operation) {
        var client = client(200, "{}");
        assertThatThrownBy(() -> invoke(client, operation)).isInstanceOf(APIError.class);
        assertThat(calls.get()).isEqualTo(1);
    }

    @ParameterizedTest
    @ValueSource(strings = {"passport", "data", "versions"})
    void rejectsEmptyBody(String operation) {
        var client = client(204, "");
        assertThatThrownBy(() -> invoke(client, operation)).isInstanceOf(APIError.class);
        assertThat(calls.get()).isEqualTo(1);
    }

    @Test
    void readsPassportAndBuildsRequest() {
        var response = client(200, """
            {"result":"OK","oid":"1.2.3","fullName":"Dictionary","version":"2.0",
             "publishDate":"19.10.2026 12:00","createDate":"18.12.2016 00:00",
             "approveDate":"31.03.2029","lastUpdate":"19.10.2026 12:00"}
            """).getPassport("1.2.3");
        assertThat(response.version()).isEqualTo("2.0");
        assertThat(response.publishDate()).isEqualTo(java.time.LocalDateTime.of(2026, 10, 19, 12, 0));
        assertThat(response.createDate()).isEqualTo(java.time.LocalDateTime.of(2016, 12, 18, 0, 0));
        assertThat(response.approveDate()).isEqualTo(java.time.LocalDate.of(2029, 3, 31));
        assertThat(response.lastUpdate()).isEqualTo(response.publishDate());
        assertThat(captured.get().url().getPath()).isEqualTo("/rest/passport");
        assertThat(captured.get().url().getQuery()).contains("identifier=1.2.3", "userKey=test-key");
    }

    @Test
    void readsDataValuesAndPaginationParameters() {
        var response = client(200, """
            {"result":"OK","total":1,"list":[[{"column":"ID","value":42},{"column":"NAME","value":"Test"}]]}
            """).getData("1.2.3", 0, 10, "ID", "asc");
        assertThat(response.list().getFirst().getFirst().value().asLong()).isEqualTo(42);
        assertThat(captured.get().url().getQuery()).contains("page=0", "size=10", "sorting=ID", "sortingDirection=ASC");
    }

    @Test
    void acceptsEmptySuccessfulVersionList() {
        var response = client(200, """
            {"result":"OK","total":0,"list":[]}
            """).getVersions("1.2.3", 0, 10);
        assertThat(response.list()).isEmpty();
    }

    @Test
    void doesNotRetryBadRequest() {
        var client = client(400, "{}");
        assertThatThrownBy(() -> client.getPassport("1.2.3"))
            .isInstanceOf(WebClientResponseException.BadRequest.class);
        assertThat(calls.get()).isEqualTo(1);
    }

    @Test
    void doesNotRetryMalformedJson() {
        var client = client(200, "{invalid");
        assertThatThrownBy(() -> client.getPassport("1.2.3"))
            .isInstanceOf(org.springframework.core.codec.DecodingException.class);
        assertThat(calls.get()).isEqualTo(1);
    }

    @ParameterizedTest
    @ValueSource(ints = {429, 503})
    void retriesTransientHttpErrorsTwice(int status) {
        var client = client(status, "{}");
        assertThatThrownBy(() -> client.getPassport("1.2.3"))
            .isInstanceOf(WebClientResponseException.class);
        assertThat(calls.get()).isEqualTo(3);
    }
}
