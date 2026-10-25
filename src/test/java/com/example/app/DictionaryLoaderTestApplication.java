package com.example.app;

import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.context.annotation.Import;
import com.example.app.config.DictionaryLoaderConfiguration;

@SpringBootConfiguration
@EnableAutoConfiguration
@Import(DictionaryLoaderConfiguration.class)
public class DictionaryLoaderTestApplication {}
