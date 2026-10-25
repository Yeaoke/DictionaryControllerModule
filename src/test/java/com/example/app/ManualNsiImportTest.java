package com.example.app;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import com.example.app.loading.services.DictionaryImportService;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(
    named = "RUN_NSI_IMPORT",
    matches = "true"
)
@SpringBootTest(
    classes = DictionaryLoaderTestApplication.class,
    properties = {
        "spring.config.import=classpath:nsi-dictionaries.yaml",
        "spring.datasource.url=${POSTGRES_URL}",
        "spring.datasource.username=${POSTGRES_USERNAME}",
        "spring.datasource.password=${POSTGRES_PASSWORD}",
        "spring.flyway.enabled=false",
        "nsi.minzdrav.base-url=https://nsi.rosminzdrav.ru/port",
        "nsi.minzdrav.user-key=${NSI_USER_KEY}",
        "nsi.minzdrav.trust-store=${NSI_TRUST_STORE}",
        "nsi.minzdrav.trust-store-password=${NSI_TRUST_STORE_PASSWORD}"
    }
)
class ManualNsiImportIT {

    @Autowired
    DictionaryImportService importService;

    @Test
    void loadSelectedDictionary() {
        String oid = System.getenv("DICTIONARY_OID");
        Long userId = Long.valueOf(System.getenv("DICTIONARY_USER_ID"));

        var result = importService.load(oid, userId);

        if (result.isEmpty()) {
            System.out.println("Эта версия уже загружена");
            return;
        }

        var batch = result.get();
        System.out.println(batch);

        assertThat(batch.status())
            .as("Результат загрузки: %s", batch)
            .isEqualTo("success");
    }
}