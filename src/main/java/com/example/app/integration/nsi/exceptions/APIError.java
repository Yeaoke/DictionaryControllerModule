package com.example.app.integration.nsi.exceptions;

public class APIError extends RuntimeException {
    private final String resultCode;
    private final String resultText;

    public APIError(String message) {
        this(message, null, null);
    }

    public APIError(String message, String resultCode, String resultText) {
        super(message);
        this.resultCode = resultCode;
        this.resultText = resultText;
    }

    public String getResultCode() { return resultCode; }
    public String getResultText() { return resultText; }
}
