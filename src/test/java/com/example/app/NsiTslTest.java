package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.time.Duration;

import javax.net.ssl.TrustManagerFactory;

import org.junit.jupiter.api.Test;

import io.netty.channel.ChannelOption;
import io.netty.handler.ssl.OpenSsl;
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslProvider;
import reactor.netty.http.client.HttpClient;

import static org.junit.jupiter.api.Assertions.assertNotNull;

class NsiTlsTest {

    @Test
    void checkNativeTls() throws Exception {
        if (!OpenSsl.isAvailable()) {
            throw new IllegalStateException(
                "Нативный TLS-провайдер не загрузился",
                OpenSsl.unavailabilityCause()
            );
        }

        System.out.println("TLS provider: " + OpenSsl.versionString());

        KeyStore store = KeyStore.getInstance("PKCS12");

        try (var input = Files.newInputStream(
                Path.of("certs", "nsi-truststore.p12"))) {
            store.load(input, "changeit".toCharArray());
        }

        TrustManagerFactory trust = TrustManagerFactory.getInstance(
            TrustManagerFactory.getDefaultAlgorithm()
        );
        trust.init(store);

        var sslContext = SslContextBuilder.forClient()
            .sslProvider(SslProvider.OPENSSL)
            .trustManager(trust)
            .build();

        HttpClient client = HttpClient.create()
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 10_000)
            .responseTimeout(Duration.ofSeconds(15))
            .secure(spec -> spec
                .sslContext(sslContext)
                .handshakeTimeout(Duration.ofSeconds(10))
            );

        String result = client.get()
            .uri(
                "https://nsi.rosminzdrav.ru/port/rest/passport"
                    + "?identifier=1.2.643.5.1.13.13.11.1009"
            )
            .responseSingle((response, body) ->
                body.asString()
                    .defaultIfEmpty("")
                    .map(text ->
                        "HTTP " + response.status().code() + "\n" + text
                    )
            )
            .block(Duration.ofSeconds(30));

        assertNotNull(result);
        System.out.println(result);
    }
}