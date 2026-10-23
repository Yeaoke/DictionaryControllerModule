package com.example.app.conrollerversion;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.test.context.SpringBootTest;

/** Only an explicitly selected disposable test database may be migrated by this test. */
@EnabledIfEnvironmentVariable(named = "TEST_DATABASE_URL", matches = ".+")
@SpringBootTest(properties = {
    "spring.datasource.url=${TEST_DATABASE_URL}",
    "spring.datasource.username=${TEST_DATABASE_USER:nsi_test}",
    "spring.datasource.password=${TEST_DATABASE_PASSWORD:}"
})
class ConrollerversionApplicationTests {
    @Test void contextLoads() {}
}
