package com.example.app.loading.services;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import com.example.app.loading.config.DictionaryCatalog.*;
import com.example.app.loading.dto.DictionarySnapshot;

@Component
public class DictionaryRowMapper {
    public List<List<Object>> map(Definition d, DictionarySnapshot snapshot) {
        if (!d.oid().equals(snapshot.oid()) || snapshot.version() == null || snapshot.version().isBlank()
                || snapshot.version().length() > 100 || snapshot.rows() == null || snapshot.rows().isEmpty()
                || snapshot.total() != snapshot.rows().size() || snapshot.total() > 100000)
            throw new IllegalArgumentException("Invalid OID/version or empty/incomplete/oversized snapshot");
        var result = new ArrayList<List<Object>>();
        var keys = new HashSet<List<Object>>();
        for (var row : snapshot.rows()) {
            if (row == null) throw new IllegalArgumentException("Null row");
            var values = new ArrayList<Object>();
            var key = new ArrayList<Object>();
            for (var c : d.columns()) {
                if (!row.containsKey(c.source())) throw new IllegalArgumentException("Missing source column " + c.source());
                Object value = convert(row.get(c.source()), c);
                if (value == null && (c.required() || d.keyColumns().contains(c.target())))
                    throw new IllegalArgumentException("Required field " + c.source());
                if (value instanceof String text && c.required() && text.isBlank())
                    throw new IllegalArgumentException("Blank field " + c.source());
                values.add(value);
                if (d.keyColumns().contains(c.target())) key.add(value);
            }
            if (!keys.add(key)) throw new IllegalArgumentException("Duplicate source key " + key);
            result.add(Collections.unmodifiableList(values));
        }
        return List.copyOf(result);
    }
    private Object convert(JsonNode node, Column c) {
        if (node == null || node.isNull()) return null;
        if (!node.isValueNode()) throw new IllegalArgumentException("Non-scalar field " + c.source());
        String text = node.asText();
        try {
            return switch (c.type()) {
                case STRING -> {
                    if (!node.isTextual()) throw new IllegalArgumentException("Expected string");
                    if (c.maxLength() != null && text.codePointCount(0, text.length()) > c.maxLength())
                        throw new IllegalArgumentException("Text too long");
                    yield text;
                }
                case LONG -> new BigDecimal(text).longValueExact();
                case INTEGER -> new BigDecimal(text).intValueExact();
                case DECIMAL -> {
                    var n = new BigDecimal(text);
                    if (c.scale() != null) n = n.setScale(c.scale(), RoundingMode.UNNECESSARY);
                    if (c.precision() != null && n.precision() > c.precision()) throw new IllegalArgumentException("Decimal overflow");
                    yield n;
                }
                case BOOLEAN -> {
                    if (!"true".equals(text) && !"false".equals(text)) throw new IllegalArgumentException("Expected boolean");
                    yield Boolean.valueOf(text);
                }
                case DATE -> LocalDate.parse(text);
                case TIMESTAMP -> LocalDateTime.parse(text);
            };
        } catch (RuntimeException ex) {
            throw new IllegalArgumentException("Invalid value for " + c.source() + " (" + c.type() + ")", ex);
        }
    }
}
