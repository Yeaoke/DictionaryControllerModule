package com.example.app.integration.nsi.dto;

/** Common business status returned by NSI, including HTTP 200 error responses. */
public interface NsiResponse {
    String result();
    String resultCode();
    String resultText();
}
