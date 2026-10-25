package com.example.app.dictionary.source;

import lombok.Getter;

@Getter
public enum DictionarySource {
    MZ("minzdrav"),
    FOMS("foms");

    private final String code;

    DictionarySource(String code) {
        this.code = code;
    }
}
