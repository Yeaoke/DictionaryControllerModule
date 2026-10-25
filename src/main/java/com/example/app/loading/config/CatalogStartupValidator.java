package com.example.app.loading.config;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import com.example.app.loading.services.DictionarySchemaValidator;

@Component
@Order(0)
public class CatalogStartupValidator implements ApplicationRunner {
    
    private final DictionaryRegistry registry;
    private final DictionarySchemaValidator validator;
    
    public CatalogStartupValidator(
        DictionaryRegistry registry,
        DictionarySchemaValidator validator
    ) {
        this.registry = registry;
        this.validator = validator;
    }
    
    public void run(ApplicationArguments args) {
        registry.all().forEach(validator::validate);
    }
}
