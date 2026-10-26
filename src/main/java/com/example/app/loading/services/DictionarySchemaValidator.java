package com.example.app.loading.services;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import com.example.app.loading.config.DictionaryCatalog.Definition;

@Component
public class DictionarySchemaValidator {
    
    private final JdbcTemplate jdbc;
    
    public DictionarySchemaValidator(
        JdbcTemplate jdbc
    ) {
        this.jdbc = jdbc;
    }
    
    public void validate(
        Definition d
    ) {
        if (jdbc.queryForObject("SELECT to_regclass(?)::text", String.class, d.stagingTable()) == null || jdbc.queryForObject("SELECT to_regclass(?)::text", String.class, d.targetTable()) == null || jdbc.queryForObject("SELECT to_regprocedure(?)::text", String.class, d.procedure() + "(bigint,character varying,character varying,bigint)") == null) {
            throw new IllegalStateException("Missing tables/procedure for " + d.entityName());
        }
        
        Boolean contract = jdbc.queryForObject("""
            SELECT prokind='p' AND proargmodes=ARRAY['i','i','i','b']::"char"[]
                AND proargnames[4]='p_batch_id'
            FROM pg_proc WHERE oid=to_regprocedure(?)
            """, Boolean.class, d.procedure() + "(bigint,character varying,character varying,bigint)");
        
        if (!Boolean.TRUE.equals(contract)) {
            throw new IllegalStateException("Invalid procedure output contract: " + d.procedure());
        }
        Map<String, String> types = jdbc.query(
            "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema='data' AND table_name=?",
            rs -> {
                Map<String, String> result = new HashMap<>();
                while (rs.next()) result.put(rs.getString("column_name"), rs.getString("data_type"));
                return result;
            }, "dsa_raw_" + d.entityName());
        for (var c : d.columns()) {
                String expected = switch (c.type()) {
                case LONG -> "bigint"; case INTEGER -> "integer"; case DECIMAL -> "numeric";
                case BOOLEAN -> "boolean"; case DATE -> "date"; case TIMESTAMP -> "timestamp without time zone";
                case STRING -> "text";
            };
            String actual = types.get(c.target());
            if (actual == null || !(expected.equals(actual) || c.type() == com.example.app.loading.config.DictionaryCatalog.ValueType.STRING && Set.of("character varying", "character").contains(actual))) {
                throw new IllegalStateException("Column type mismatch: " + d.stagingTable() + "." + c.target());
            }
        }
        var pk = jdbc.queryForList("""
            SELECT a.attname FROM pg_index i
            JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
            WHERE i.indrelid=to_regclass(?) AND i.indisprimary
            """, String.class, d.targetTable());
        if (!new HashSet<>(pk).equals(new HashSet<>(d.keyColumns()))) {
            throw new IllegalStateException("Primary key mismatch: " + d.entityName());
        }
    }
}
