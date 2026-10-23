package com.example.app.sync;

import java.math.BigDecimal;
import java.time.*;
import java.time.format.*;
import java.util.*;
import tools.jackson.databind.JsonNode;

public final class SourceValues {
    private SourceValues() {}
    public static Map<String, JsonNode> fields(JsonNode row) {
        Map<String, JsonNode> fields = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        if (!row.isArray()) throw new IllegalArgumentException("Строка НСИ должна быть массивом полей");
        for (var item : row) {
            String name = item.path("column").asText("");
            if (name.isBlank() || fields.containsKey(name) || !item.has("value"))
                throw new IllegalArgumentException("Пустое/повторное поле или отсутствующее value в строке НСИ");
            fields.put(name, item.get("value"));
        }
        return fields;
    }
    public static Object convert(JsonNode value, String type) {
        if (value == null || value.isNull()) return null;
        if (type.equals("text") || type.startsWith("varchar"))
            return value.isValueNode() ? value.asText() : value.toString();
        if (!value.isValueNode()) throw new IllegalArgumentException("Ожидалось скалярное значение");
        String s = value.asText().strip();
        if (s.isEmpty()) return null;
        if (type.equals("bigint")) return new BigDecimal(s).longValueExact();
        if (type.equals("integer")) return new BigDecimal(s).intValueExact();
        if (type.startsWith("numeric")) {
            int comma = type.indexOf(',');
            int scale = comma < 0 ? 0 : Integer.parseInt(type.substring(comma+1,type.indexOf(')')).strip());
            return new BigDecimal(s).setScale(scale, java.math.RoundingMode.UNNECESSARY);
        }
        if (type.equals("boolean")) return switch (s.toLowerCase(Locale.ROOT)) {
            case "true", "1" -> true;
            case "false", "0" -> false;
            default -> throw new IllegalArgumentException("Некорректное логическое значение");
        };
        if (type.equals("timestamp without time zone")) return timestamp(s);
        throw new IllegalArgumentException("Неподдерживаемый тип: " + type);
    }
    static LocalDateTime timestamp(String s) {
        try { return OffsetDateTime.parse(s).withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime(); }
        catch (DateTimeParseException ignored) {}
        for (var f : List.of(DateTimeFormatter.ISO_LOCAL_DATE_TIME,
                DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss[.SSS]").withResolverStyle(ResolverStyle.STRICT),
                DateTimeFormatter.ofPattern("dd.MM.uuuu HH:mm[:ss]").withResolverStyle(ResolverStyle.STRICT))) {
            try { return LocalDateTime.parse(s, f); } catch (DateTimeParseException ignored) {}
        }
        for (var f : List.of(DateTimeFormatter.ISO_LOCAL_DATE,
                DateTimeFormatter.ofPattern("dd.MM.uuuu").withResolverStyle(ResolverStyle.STRICT))) {
            try { return LocalDate.parse(s, f).atStartOfDay(); } catch (DateTimeParseException ignored) {}
        }
        throw new IllegalArgumentException("Неподдерживаемый формат даты");
    }
}
