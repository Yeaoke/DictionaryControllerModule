package com.example.app.loading.dto;

import java.util.HashSet;
import java.util.List;
import com.example.app.dictionary.dto.DirectionTypeRowDTO;

/** Complete, validated snapshot; also the JSON file import format. */
public record DirectionTypeSnapshot(String oid, String version, long total, List<DirectionTypeRowDTO> rows) {
    public static final String OID = "1.2.643.5.1.13.13.11.1009";
    public DirectionTypeSnapshot {
        if (!OID.equals(oid)) throw new IllegalArgumentException("Wrong dictionary OID");
        if (version == null || version.isBlank() || version.length() > 100)
            throw new IllegalArgumentException("Version is required (max 100)");
        if (rows == null || rows.isEmpty() || total != rows.size() || total > 100000)
            throw new IllegalArgumentException("Empty, incomplete or oversized snapshot");
        rows = List.copyOf(rows);
        var ids = new HashSet<Long>();
        for (var row : rows) {
            if (row.id() == null || !ids.add(row.id()))
                throw new IllegalArgumentException("Missing or duplicate source ID");
            if (row.name() == null || row.name().isBlank() || length(row.name()) > 100)
                throw new IllegalArgumentException("NAME is required (max 100), ID=" + row.id());
            if (row.doc() != null && length(row.doc()) > 100)
                throw new IllegalArgumentException("DOC exceeds 100, ID=" + row.id());
            if (row.sort() != null && (row.sort() < -9999999999L || row.sort() > 9999999999L))
                throw new IllegalArgumentException("SORT exceeds numeric(10), ID=" + row.id());
            if (row.rejectReason() != null || row.newId() != null)
                throw new IllegalArgumentException("Input must not contain processing results");
        }
    }
    private static int length(String value) { return value.codePointCount(0, value.length()); }
}
