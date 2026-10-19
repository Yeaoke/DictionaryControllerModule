package com.example.app.integration.nsi.exceptions;

public class APIError extends RuntimeException {
    public APIError(String message) {
        super(message);
    }
}
