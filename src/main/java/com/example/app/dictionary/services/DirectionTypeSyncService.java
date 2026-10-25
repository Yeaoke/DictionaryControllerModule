package com.example.app.dictionary.services;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;
import com.example.app.dictionary.dto.DirectionTypeRowDTO;
import com.example.app.integration.nsi.client.NsiMizdravClient;
import com.example.app.integration.nsi.mapper.DirectionTypeRowMapper;
import com.example.app.loading.dto.DirectionTypeSnapshot;
import com.example.app.loading.dto.DirectionTypeLoadResultDTO;
import com.example.app.loading.repos.LoadedVersionJdbcRepository;
import com.example.app.loading.services.DirectionTypeApplyService;

@Service
@Transactional(propagation = Propagation.NEVER)
public class DirectionTypeSyncService {
    private final NsiMizdravClient client;
    private final DirectionTypeRowMapper mapper;
    private final LoadedVersionJdbcRepository versions;
    private final DirectionTypeApplyService apply;
    private final String baseUrl;
    public DirectionTypeSyncService(NsiMizdravClient client, DirectionTypeRowMapper mapper,
            LoadedVersionJdbcRepository versions, DirectionTypeApplyService apply,
            @Value("${nsi.minzdrav.base-url}") String baseUrl) {
        this.client = client; this.mapper = mapper; this.versions = versions;
        this.apply = apply; this.baseUrl = baseUrl;
    }

    public Optional<DirectionTypeLoadResultDTO> sync(Long userId) {
        if (userId == null) throw new IllegalArgumentException("userId is required");
        String expected = versions.findVersionByEntityName("direction_type").orElse(null);
        var passport = client.getPassport(DirectionTypeSnapshot.OID);
        if (passport == null || !DirectionTypeSnapshot.OID.equals(passport.oid())
                || passport.version() == null || passport.version().isBlank()
                || passport.rowsCount() == null || passport.rowsCount() <= 0 || passport.rowsCount() > 100000)
            throw new IllegalStateException("Invalid passport OID, version or row count");
        if (passport.version().equals(expected)) return Optional.empty();
        var rows = new ArrayList<DirectionTypeRowDTO>();
        var ids = new HashSet<Long>();
        for (int page = 1; rows.size() < passport.rowsCount(); page++) {
            var response = client.getData(DirectionTypeSnapshot.OID, passport.version(), page, 500, "ID", "ASC");
            if (response == null || response.total() == null || response.total().longValue() != passport.rowsCount()
                    || response.list() == null || response.list().isEmpty() || response.list().size() > 500)
                throw new IllegalStateException("Incomplete NSI page " + page);
            for (var item : response.list()) {
                var row = mapper.map(item);
                if (row.id() == null || !ids.add(row.id()))
                    throw new IllegalStateException("Missing/duplicate ID on page " + page);
                rows.add(row);
            }
            if (rows.size() > passport.rowsCount()) throw new IllegalStateException("NSI row count changed");
        }
        var after = client.getPassport(DirectionTypeSnapshot.OID);
        if (after == null || !DirectionTypeSnapshot.OID.equals(after.oid())
                || !passport.version().equals(after.version()) || !passport.rowsCount().equals(after.rowsCount()))
            throw new IllegalStateException("NSI passport changed during download; retry");
        var snapshot = new DirectionTypeSnapshot(DirectionTypeSnapshot.OID, passport.version(), passport.rowsCount(), rows);
        // No userKey in the journal URL.
        return apply.apply(snapshot, userId, baseUrl + "/rest/data?identifier=" + DirectionTypeSnapshot.OID, expected);
    }

    public Optional<DirectionTypeLoadResultDTO> loadFile(Path file, Long userId) throws IOException {
        if (userId == null) throw new IllegalArgumentException("userId is required");
        String expected = versions.findVersionByEntityName("direction_type").orElse(null);
        // Bound bytes read even when the file changes while being read.
        byte[] bytes;
        try (var input = Files.newInputStream(file)) { bytes = input.readNBytes(20 * 1024 * 1024 + 1); }
        if (bytes.length > 20 * 1024 * 1024) throw new IllegalArgumentException("JSON file exceeds 20 MiB");
        var snapshot = JsonMapper.builder().build().readValue(bytes, DirectionTypeSnapshot.class);
        return apply.apply(snapshot, userId, file.toAbsolutePath().normalize().toUri().toString(), expected);
    }
}
