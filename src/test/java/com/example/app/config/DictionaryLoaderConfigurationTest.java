package com.example.app.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.reactive.function.client.WebClient;
import com.example.app.loading.services.DictionaryImportService;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class DictionaryLoaderConfigurationTest {
    @Test
    void hostCanImportLibraryWithoutStartingJobsOrTouchingDatabase() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        new ApplicationContextRunner()
            .withUserConfiguration(DictionaryLoaderConfiguration.class)
            .withBean(JdbcTemplate.class, () -> jdbc)
            .withBean(PlatformTransactionManager.class, () -> mock(PlatformTransactionManager.class))
            .withBean(WebClient.Builder.class, WebClient::builder)
            .withPropertyValues(
                "nsi.minzdrav.base-url=https://example.test",
                "nsi.minzdrav.user-key=test-key",
                "nsi.minzdrav.trust-store=certs/nsi-truststore.p12",
                "nsi.minzdrav.trust-store-password=changeit",
                "dictionaries.definitions[0].oid=1.2.3",
                "dictionaries.definitions[0].entity-name=patient_sex",
                "dictionaries.definitions[0].staging-table=data.dsa_raw_patient_sex",
                "dictionaries.definitions[0].target-table=data.patient_sex",
                "dictionaries.definitions[0].procedure=dsa_data_load.load_patient_sex",
                "dictionaries.definitions[0].key-columns[0]=id",
                "dictionaries.definitions[0].sorting=ID",
                "dictionaries.definitions[0].columns[0].source=ID",
                "dictionaries.definitions[0].columns[0].target=id",
                "dictionaries.definitions[0].columns[0].type=LONG",
                "dictionaries.definitions[0].columns[0].required=true")
            .run(context -> {
                assertThat(context).hasNotFailed().hasSingleBean(DictionaryImportService.class);
                assertThat(context.getBeansOfType(org.springframework.boot.ApplicationRunner.class)).isEmpty();
                verify(jdbc).afterPropertiesSet(); // Spring bean lifecycle, no SQL.
                verifyNoMoreInteractions(jdbc);
            });
    }
}
