package com.example.app.sync;

import java.util.*;
import java.util.concurrent.RejectedExecutionException;
import org.springframework.dao.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import tools.jackson.databind.JsonNode;

@RestController
@RequestMapping("/api")
public class SyncController {
    private final DictionaryCatalog catalog;
    private final SyncService service;
    private final SyncStore store;
    public SyncController(DictionaryCatalog catalog, SyncService service, SyncStore store) {
        this.catalog=catalog; this.service=service; this.store=store;
    }
    @GetMapping("/dictionaries")
    public List<Map<String,Object>> dictionaries() {
        return catalog.all().stream().map(d -> {
            Map<String,Object> result = new LinkedHashMap<>();
            result.put("name",d.name()); result.put("oid",d.oid());
            result.put("loadedVersion",store.loadedVersion(d.name()));
            result.put("keys",d.keys()); result.put("columns",d.columns());
            return result;
        }).toList();
    }
    @PostMapping("/dictionaries/{name}/sync")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public Map<String,Object> sync(@PathVariable String name, @RequestBody SyncService.Request request) {
        return Map.of("runId",service.submit(name,request),"status","queued");
    }
    @PostMapping("/dictionaries/sync")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public List<Map<String,Object>> syncAll(@RequestBody SyncService.Request request) { return service.submitAll(request); }
    @GetMapping("/sync-runs/{id}")
    public Map<String,Object> run(@PathVariable UUID id) { return store.run(id); }
    @PostMapping("/sync-runs/{id}/recover")
    public Map<String,Object> recover(@PathVariable UUID id) { service.recover(id); return store.run(id); }
    @GetMapping("/sync-runs/{id}/pages/{kind}/{page}")
    public JsonNode page(@PathVariable UUID id, @PathVariable String kind, @PathVariable int page) {
        if ((!kind.equals("data") && !kind.equals("versions")) || page<0) throw new IllegalArgumentException("Неверная страница");
        return store.page(id,kind,page);
    }
    @GetMapping("/dictionaries/{name}/runs")
    public List<Map<String,Object>> history(@PathVariable String name,
        @RequestParam(defaultValue="50") int limit, @RequestParam(defaultValue="0") int offset) {
        catalog.get(name); pagination(limit,offset); return store.history(name,limit,offset);
    }
    @GetMapping("/dictionaries/{name}/rows")
    public List<Map<String,Object>> rows(@PathVariable String name,
        @RequestParam(defaultValue="100") int limit, @RequestParam(defaultValue="0") int offset,
        @RequestParam(defaultValue="false") boolean includeDeleted) {
        pagination(limit,offset); return store.rows(catalog.get(name),limit,offset,includeDeleted);
    }
    @GetMapping("/dictionaries/{name}/versions")
    public List<JsonNode> versions(@PathVariable String name,
        @RequestParam(defaultValue="100") int limit, @RequestParam(defaultValue="0") int offset) {
        catalog.get(name); pagination(limit,offset); return store.versions(name,limit,offset);
    }
    @GetMapping("/dictionaries/{name}/passport")
    public JsonNode passport(@PathVariable String name, @RequestParam(required=false) String version) {
        catalog.get(name);
        if (version == null) version=store.loadedVersion(name);
        if (version == null) throw new NoSuchElementException("Нет загруженной версии; укажите version");
        return store.passport(name,version);
    }
    static void pagination(int limit,int offset) {
        if (limit<1 || limit>1000 || offset<0) throw new IllegalArgumentException("limit: 1..1000, offset: >=0");
    }
    @RestControllerAdvice
    public static class Errors {
        @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class)
        public ResponseEntity<Map<String,String>> unreadable() {
            return error(400,"Ожидается JSON-объект с числовым userId; force и allowEmpty — необязательные true/false");
        }
        @ExceptionHandler(NoSuchElementException.class)
        public ResponseEntity<Map<String,String>> missing(NoSuchElementException e) { return error(404,e.getMessage()); }
        @ExceptionHandler(IllegalArgumentException.class)
        public ResponseEntity<Map<String,String>> bad(IllegalArgumentException e) { return error(400,e.getMessage()); }
        @ExceptionHandler(DuplicateKeyException.class)
        public ResponseEntity<Map<String,String>> conflict() { return error(409,"Для справочника уже есть активная загрузка"); }
        @ExceptionHandler(IllegalStateException.class)
        public ResponseEntity<Map<String,String>> state(IllegalStateException e) { return error(409,e.getMessage()); }
        @ExceptionHandler(RejectedExecutionException.class)
        public ResponseEntity<Map<String,String>> full() { return error(503,"Очередь заполнена или приложение останавливается"); }
        @ExceptionHandler(DataAccessException.class)
        public ResponseEntity<Map<String,String>> database() { return error(503,"База данных недоступна или схема не соответствует модулю"); }
        private ResponseEntity<Map<String,String>> error(int status,String message) {
            return ResponseEntity.status(status).body(Map.of("error",message==null ? "Ошибка запроса" : message));
        }
    }
}
