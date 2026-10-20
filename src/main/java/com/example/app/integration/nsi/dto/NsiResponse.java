package com.example.app.integration.nsi.dto;

public record NsiResponse(
    String result,
    String resultCode,
    String resultText
) {}