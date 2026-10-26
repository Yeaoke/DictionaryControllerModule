package com.example.app.loading.services;

import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;

/** Checks bytes actually consumed, including files that grow after Files.size(). */
final class LimitedInputStream extends FilterInputStream {
    private final long limit;
    private long count;
    LimitedInputStream(InputStream input, long limit) {
        super(input);
        if (limit < 0) throw new IllegalArgumentException("Negative byte limit");
        this.limit = limit;
    }
    private void consumed(long bytes) throws IOException {
        count += bytes;
        if (count > limit) throw new IOException("JSON file exceeds " + limit + " bytes");
    }
    @Override public int read() throws IOException {
        int value = in.read();
        if (value != -1) consumed(1);
        return value;
    }
    @Override public int read(byte[] bytes, int offset, int length) throws IOException {
        int read = in.read(bytes, offset, (int) Math.min(length, limit - count + 1));
        if (read > 0) consumed(read);
        return read;
    }
    @Override public long skip(long requested) throws IOException {
        if (requested <= 0) return 0;
        long skipped = in.skip(Math.min(requested, limit - count + 1));
        consumed(skipped);
        return skipped;
    }
    @Override public boolean markSupported() { return false; }
    @Override public synchronized void mark(int readlimit) { }
    @Override public synchronized void reset() throws IOException { throw new IOException("Reset unsupported"); }
}
