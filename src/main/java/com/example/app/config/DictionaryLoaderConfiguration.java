package com.example.app.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import com.example.app.integration.nsi.client.NsiMizdravClient;
import com.example.app.loading.config.DictionaryRegistry;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;
import com.example.app.loading.services.*;

@Configuration(proxyBeanMethods = false)
@EnableTransactionManagement
@Import({
    WebClientConfig.class, NsiMizdravClient.class, DictionaryRegistry.class,
    LoadedVersionJdbcRepository.class, DictionarySchemaValidator.class,
    DictionaryRowMapper.class, DictionaryProcedureService.class,
    DictionaryApplyService.class, DictionaryImportService.class
})
public class DictionaryLoaderConfiguration {}
