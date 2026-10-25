package com.example.app.config;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.time.Duration;

import javax.net.ssl.TrustManagerFactory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;

import io.netty.channel.ChannelOption;
import io.netty.handler.ssl.OpenSsl;
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslProvider;
import reactor.netty.http.client.HttpClient;

@Configuration(proxyBeanMethods = false)
public class WebClientConfig {

    @Bean("minzdravWebClient")
    @ConditionalOnMissingBean(name = "minzdravWebClient")
    WebClient minzdravWebClient(
        WebClient.Builder builder,
        @Value("${nsi.minzdrav.base-url}") String baseUrl,
        @Value("${nsi.minzdrav.trust-store:certs/nsi-truststore.p12}")
        String trustStorePath,
        @Value("${nsi.minzdrav.trust-store-password}")
        String trustStorePassword
    ) throws Exception {

        if (!OpenSsl.isAvailable()) {
            throw new IllegalStateException(
                "Не удалось загрузить BoringSSL",
                OpenSsl.unavailabilityCause()
            );
        }

        KeyStore store = KeyStore.getInstance("PKCS12");

        try (var input = Files.newInputStream(Path.of(trustStorePath))) {
            store.load(input, trustStorePassword.toCharArray());
        }

        TrustManagerFactory trust = TrustManagerFactory.getInstance(
            TrustManagerFactory.getDefaultAlgorithm()
        );
        trust.init(store);

        var sslContext = SslContextBuilder.forClient()
            .sslProvider(SslProvider.OPENSSL)
            .trustManager(trust)
            .build();

        HttpClient httpClient = HttpClient.create()
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 10_000)
            .responseTimeout(Duration.ofSeconds(60))
            .secure(spec -> spec
                .sslContext(sslContext)
                .handshakeTimeout(Duration.ofSeconds(10))
            );

        return builder.clone()
            .baseUrl(baseUrl)
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .codecs(configurer -> configurer.defaultCodecs().maxInMemorySize(32 * 1024 * 1024))
            .build();
    }
}
