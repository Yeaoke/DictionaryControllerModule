package com.example.app.sync;

import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;
import static org.junit.jupiter.api.Assertions.*;

class NsiSourceClientTest {
    @Test void pinsVersionAndDoesNotRequestAColumnSubset() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        var uri = new AtomicReference<URI>();
        server.createContext("/rest/data",e -> {
            uri.set(e.getRequestURI());
            byte[] bytes = "{\"result\":\"OK\",\"list\":[],\"total\":0}".getBytes(StandardCharsets.UTF_8);
            e.getResponseHeaders().add("Content-Type","application/json");
            e.sendResponseHeaders(200,bytes.length);
            e.getResponseBody().write(bytes); e.close();
        });
        server.start();
        try {
            var client = new NsiSourceClient(WebClient.builder()
                .baseUrl("http://127.0.0.1:"+server.getAddress().getPort()).build(),"test-secret");
            assertTrue(client.page("data","1.2.3","2.4",0,50).path("list").isArray());
            assertTrue(uri.get().getQuery().contains("version=2.4"));
            assertTrue(uri.get().getQuery().contains("page=0"));
            assertFalse(uri.get().getQuery().contains("columns"));
        } finally { server.stop(0); }
    }
    @Test void errorNeverExposesApiKeyOrResponseBody() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/rest/passport",e -> { e.sendResponseHeaders(401,-1); e.close(); });
        server.start();
        try {
            var client = new NsiSourceClient(WebClient.builder()
                .baseUrl("http://127.0.0.1:"+server.getAddress().getPort()).build(),"test-secret");
            var error=assertThrows(IllegalStateException.class,()->client.passport("1.2.3",null));
            assertEquals("НСИ HTTP 401: passport",error.getMessage());
            assertNull(error.getCause());
        } finally { server.stop(0); }
    }
}
