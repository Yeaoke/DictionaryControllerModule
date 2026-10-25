package com.example.app.config;

import java.util.ArrayList;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.http.HttpStatus;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import static org.assertj.core.api.Assertions.assertThat;

class WebClientConfigTest {
    @Test void doesNotChangeHostBuilder() throws Exception {
        var urls = new ArrayList<String>();
        var builder = WebClient.builder().baseUrl("https://host.example").exchangeFunction(request -> {
            urls.add(request.url().toString());
            return Mono.just(ClientResponse.create(HttpStatus.OK).build());
        });
        var nsi = new WebClientConfig().minzdravWebClient(builder, "https://nsi.example",
            "certs/nsi-truststore.p12", "changeit");
        nsi.get().uri("/test").retrieve().toBodilessEntity().block();
        builder.build().get().uri("/test").retrieve().toBodilessEntity().block();
        assertThat(urls).containsExactly("https://nsi.example/test", "https://host.example/test");
    }

    @Test void hostCanSupplyItsOwnTlsClientWithoutLibraryTruststore() {
        var client = WebClient.create();
        new ApplicationContextRunner().withUserConfiguration(WebClientConfig.class)
            .withBean("minzdravWebClient", WebClient.class, () -> client)
            .run(context -> {
                assertThat(context).hasNotFailed().hasSingleBean(WebClient.class);
                assertThat(context.getBean("minzdravWebClient")).isSameAs(client);
            });
    }
}
