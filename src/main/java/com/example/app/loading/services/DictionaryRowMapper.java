package com.example.app.loading.services;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;
import java.util.*;
import java.util.function.Consumer;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import com.example.app.loading.config.DictionaryCatalog.*;
import com.example.app.loading.dto.DictionarySnapshot;

@Component
public class DictionaryRowMapper {

    private static final DateTimeFormatter NSI_DATE = DateTimeFormatter.ofPattern("dd.MM.uuuu", Locale.ROOT).withResolverStyle(ResolverStyle.STRICT);

    public void validateSnapshot(Definition d, DictionarySnapshot snapshot) {
        if (snapshot == null || !d.oid().equals(snapshot.oid()) || snapshot.version() == null
                || snapshot.version().isBlank() || snapshot.version().length() > 100
                || snapshot.rows() == null || snapshot.rows().isEmpty()
                || snapshot.total() != snapshot.rows().size() || snapshot.total() > 100000) {
            throw new IllegalArgumentException("Invalid OID/version or empty/incomplete/oversized snapshot");
        }
    }

    public List<List<Object>> map(
        Definition d,
        DictionarySnapshot snapshot
    ) {
        validateSnapshot(d, snapshot);

        var result = new ArrayList<List<Object>>(snapshot.rows().size());
        
        forEachBatch(d, snapshot, 500, result::addAll);
        
        return Collections.unmodifiableList(result);
    }

    public void forEachBatch(
        Definition d,
        DictionarySnapshot snapshot,
        int batchSize,
        Consumer<List<List<Object>>> consumer
    ) {
        validateSnapshot(d, snapshot);

        if (batchSize < 1) {
            throw new IllegalArgumentException("Positive batch size required");
        }
        
        var keyColumns = new HashSet<>(d.keyColumns());
        boolean[] keyFlags = new boolean[d.columns().size()];
        
        for (int i = 0; i < keyFlags.length; i++) {
            keyFlags[i] = keyColumns.contains(d.columns().get(i).target());
        }
        
        var keys = HashSet.<Object>newHashSet(snapshot.rows().size());
        var batch = new ArrayList<List<Object>>(Math.min(batchSize, snapshot.rows().size()));
        
        for (var row : snapshot.rows()) {
            if (row == null) {
                throw new IllegalArgumentException("Null row");
            }
            
            var values = new ArrayList<Object>(d.columns().size());
            var compound = keyColumns.size() == 1 ? null : new ArrayList<Object>(keyColumns.size());
            
            Object scalarKey = null;
            
            for (int i = 0; i < d.columns().size(); i++) {
                var column = d.columns().get(i);
                if (!row.containsKey(column.source())) {
                    throw new IllegalArgumentException("Missing source column " + column.source());
                }
                
                Object value = convert(row.get(column.source()), column);
                
                if (value == null && (column.required() || keyFlags[i])) {
                    throw new IllegalArgumentException("Required field " + column.source());
                }
                
                if (value instanceof String text && column.required() && text.isBlank()) {
                    throw new IllegalArgumentException("Blank field " + column.source());
                }
                
                values.add(value);
                
                if (keyFlags[i]) {
                    Object keyValue = value instanceof BigDecimal number ? number.stripTrailingZeros() : value;
                    if (compound == null) {
                        scalarKey = keyValue;
                    } else {
                        compound.add(keyValue);
                    }
                }
            }

            Object key = compound == null ? scalarKey : List.copyOf(compound);
            if (!keys.add(key)) {
                throw new IllegalArgumentException("Duplicate source key " + key);
            }
            batch.add(Collections.unmodifiableList(values));
            
            if (batch.size() == batchSize) {
                consumer.accept(Collections.unmodifiableList(batch));
                batch = new ArrayList<>(Math.min(batchSize, snapshot.rows().size()));
            }
        }
        if (!batch.isEmpty()) {
            consumer.accept(Collections.unmodifiableList(batch));
        }
    }

    private Object convert(
        JsonNode node,
        Column c
    ) {
        if (node == null || node.isNull()) {
            return null;
        }
        if (!node.isValueNode()) {
            throw new IllegalArgumentException("Non-scalar field " + c.source());
        }
        
        String text = node.asText();
        try {
            return switch (c.type()) {
                case STRING -> {
                    if (!node.isTextual()) {
                        throw new IllegalArgumentException("Expected string");
                    }
                    if (c.maxLength() != null && text.codePointCount(0, text.length()) > c.maxLength()) {
                        throw new IllegalArgumentException("Text too long");
                    }
                    yield text;
                }
                case LONG -> new BigDecimal(text).longValueExact();
                case INTEGER -> new BigDecimal(text).intValueExact();
                case DECIMAL -> {
                    var n = new BigDecimal(text);
                    if (c.scale() != null) {
                        n = n.setScale(c.scale(), RoundingMode.UNNECESSARY);
                    }
                    if (c.precision() != null && n.precision() > c.precision()) {
                        throw new IllegalArgumentException("Decimal overflow");
                    }
                    yield n;
                }
                case BOOLEAN -> {
                    if (!"true".equals(text) && !"false".equals(text)) {
                        throw new IllegalArgumentException("Expected boolean");
                    }
                    yield Boolean.valueOf(text);
                }
                case DATE -> parseDate(text);
                case TIMESTAMP -> parseTimestamp(text);
            };
        } catch (RuntimeException ex) {
            throw new IllegalArgumentException("Invalid value for " + c.source() + " (" + c.type() + ")", ex);
        }
    }

    private static LocalDate parseDate(String text) {
        String value = text.strip();

        try {
            return LocalDate.parse(value, DateTimeFormatter.ISO_LOCAL_DATE);
        } catch (DateTimeParseException ignored) {
            return LocalDate.parse(value, NSI_DATE);
        }
    }

    private static LocalDateTime parseTimestamp(String text) {
        String value = text.strip();

        try {
            return LocalDateTime.parse(
                value,
                DateTimeFormatter.ISO_LOCAL_DATE_TIME
            );
        } catch (DateTimeParseException ignored) {
            return parseDate(value).atStartOfDay();
        }
    }
}
