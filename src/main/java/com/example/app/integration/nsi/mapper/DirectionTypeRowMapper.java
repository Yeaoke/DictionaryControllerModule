package com.example.app.integration.nsi.mapper;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.example.app.dictionary.dto.DirectionTypeRowDTO;
import com.example.app.integration.nsi.dto.NsiDataPageResponse.DataItem;

import tools.jackson.databind.JsonNode;

@Component
public class DirectionTypeRowMapper {

    private static final String ID = "ID";
    private static final String NAME = "NAME";
    private static final String DOC = "DOC";
    private static final String SORT = "SORT";

    public DirectionTypeRowDTO toDto(List<DataItem> row) {
        if (row == null || row.isEmpty()) {
            throw new IllegalArgumentException(
                "Строка справочника не должна быть пустой"
            );
        }

        Map<String, JsonNode> fields = new HashMap<>();

        for (DataItem item : row) {
            if (item == null || item.column() == null || item.column().isBlank()) {

                throw new IllegalArgumentException(
                    "В строке отсутствует название поля"
                );
            }

            if (fields.containsKey(item.column())) {
                throw new IllegalArgumentException(
                    "Поле повторяется в строке: " + item.column()
                );
            }

            fields.put(item.column(), item.value());
        }

        Long id = readLong(fields, ID);
        String name = readString(fields, NAME);
        String doc = readString(fields, DOC);
        Long sort = readLong(fields, SORT);

        if (id == null) {
            throw new IllegalArgumentException(
                "Отсутствует обязательное поле " + ID
            );
        }

        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException(
                "Отсутствует название для записи ID=" + id
            );
        }

        return new DirectionTypeRowDTO(
            id,
            name,
            doc,
            sort,
            null, // rejectReason заполняется при обработке загрузки
            null  // newId заполняется после принятия записи
        );
    }

    private String readString(
        Map<String, JsonNode> fields,
        String field
    ) {
        JsonNode value = fields.get(field);

        if (value == null || value.isNull()) {
            return null;
        }

        if (!value.isTextual()) {
            throw new IllegalArgumentException(
                "Поле " + field + " должно содержать строку"
            );
        }

        return value.asText();
    }

    private Long readLong(
        Map<String, JsonNode> fields,
        String field
    ) {
        JsonNode value = fields.get(field);

        if (value == null || value.isNull()) {
            return null;
        }

        if (value.isIntegralNumber() && value.canConvertToLong()) {
            return value.longValue();
        }

        if (value.isTextual()) {
            String text = value.asText().strip();

            if (!text.isEmpty()) {
                try {
                    return Long.valueOf(text);
                } catch (NumberFormatException exception) {
                    throw new IllegalArgumentException(
                        "Поле " + field + " содержит неверное целое число",
                        exception
                    );
                }
            }
        }

        throw new IllegalArgumentException(
            "Поле " + field + " должно содержать целое число типа Long"
        );
    }
}