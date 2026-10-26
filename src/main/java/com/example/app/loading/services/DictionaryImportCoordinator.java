package com.example.app.loading.services;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.stereotype.Component;
import com.example.app.loading.config.DictionaryLoadProperties;

@Component
public class DictionaryImportCoordinator {
    private final Semaphore slots;
    private final Set<String> active = ConcurrentHashMap.newKeySet();

    public DictionaryImportCoordinator(
        DictionaryLoadProperties properties
    ) {
        slots = new Semaphore(properties.maxConcurrentImports());
    }

    public Lease acquire(String oid) {
        if (!active.add(oid)) throw new IllegalStateException("Import already running for OID: " + oid);
        if (!slots.tryAcquire()) {
            active.remove(oid);
            throw new IllegalStateException("Concurrent import limit reached; retry later");
        }
        return new Lease(oid);
    }

    public final class Lease implements AutoCloseable {
        private final String oid;
        private final AtomicBoolean closed = new AtomicBoolean();
        private Lease(String oid) { this.oid = oid; }
        @Override public void close() {
            if (closed.compareAndSet(false, true)) {
                slots.release();
                active.remove(oid);
            }
        }
    }
}
