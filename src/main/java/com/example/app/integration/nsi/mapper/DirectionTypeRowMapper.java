package com.example.app.integration.nsi.mapper;

import java.util.HashMap;
import java.util.List;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import com.example.app.integration.nsi.dto.NsiDataPageResponse.DataItem;
import com.example.app.dictionary.dto.DirectionTypeRowDTO;

@Component
public class DirectionTypeRowMapper {
    public DirectionTypeRowDTO map(List<DataItem> items) {
        if (items == null) throw new IllegalArgumentException("Missing row");
        var fields = new HashMap<String, JsonNode>();
        for (var item : items) {
            if (item == null || item.column() == null || fields.containsKey(item.column()))
                throw new IllegalArgumentException("Missing or duplicate column");
            fields.put(item.column(), item.value());
        }
        if (!fields.keySet().containsAll(List.of("ID", "NAME", "DOC", "SORT")))
            throw new IllegalArgumentException("Expected source columns: ID, NAME, DOC, SORT");
        return new DirectionTypeRowDTO(number(fields.get("ID")), text(fields.get("NAME")),
            text(fields.get("DOC")), number(fields.get("SORT")), null, null);
    }

    private String text(JsonNode value) {
        if (value == null || value.isNull()) return null;
        if (!value.isTextual()) throw new IllegalArgumentException("Expected text: " + value);
        return value.asText();
    }

    private Long number(JsonNode value) {
        if (value == null || value.isNull()) return null;
        if (value.isIntegralNumber() && value.canConvertToLong()) return value.longValue();
        if (value.isTextual()) return Long.valueOf(value.asText().strip());
        throw new IllegalArgumentException("Expected integer: " + value);
    }
}
