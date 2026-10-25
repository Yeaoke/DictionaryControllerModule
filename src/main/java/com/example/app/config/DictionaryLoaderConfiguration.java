package com.example.app.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import com.example.app.integration.nsi.client.NsiMizdravClient;
import com.example.app.loading.config.DictionaryRegistry;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;
import com.example.app.loading.services.*;

/**
 * Explicit library entry point. The host supplies one JdbcTemplate and transaction
 * manager and imports nsi-dictionaries.yaml (or its own catalog).
 * No startup runners, controllers, migrations or component scanning are enabled.
 */
@Configuration(proxyBeanMethods = false)
@EnableTransactionManagement
@Import({
    WebClientConfig.class, NsiMizdravClient.class, DictionaryRegistry.class,
    LoadedVersionJdbcRepository.class, DictionarySchemaValidator.class,
    DictionaryRowMapper.class, DictionaryProcedureService.class,
    DictionaryApplyService.class, DictionaryImportService.class
})
public class DictionaryLoaderConfiguration {}
