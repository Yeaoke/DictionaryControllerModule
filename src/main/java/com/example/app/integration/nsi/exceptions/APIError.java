package com.example.app.integration.nsi.exceptions;

public class ApiError extends RuntimeException {

    private final String resultCode;
    private final String resultText;

    public ApiError(String message) {
        this(message, null, null);
    }

    public ApiError(
        String message,
        String resultCode,
        String resultText
    ) {
        super(message);
        this.resultCode = resultCode;
        this.resultText = resultText;
    }

    public String getResultCode() {
        return resultCode;
    }

    public String getResultText() {
        return resultText;
    }
}