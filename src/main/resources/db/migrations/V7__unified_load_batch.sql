-- Keep the original batch identity and expose a UUID for asynchronous API calls.
ALTER TABLE data.dsa_load_batch
    ADD COLUMN run_id uuid NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN oid text,
    ADD COLUMN requested_version text,
    ADD COLUMN user_id bigint,
    ADD COLUMN force_reload boolean NOT NULL DEFAULT false,
    ADD COLUMN allow_empty boolean NOT NULL DEFAULT false,
    ADD COLUMN created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN passport jsonb,
    ADD CONSTRAINT dsa_load_batch_run_id_key UNIQUE (run_id),
    ALTER COLUMN load_procedure_name DROP NOT NULL;

UPDATE data.dsa_load_batch SET created_at = started_at;

-- Transfer every existing run, keeping UUIDs and raw-page relationships intact.
INSERT INTO data.dsa_load_batch (
    run_id, entity_name, oid, requested_version, new_version, user_id,
    force_reload, allow_empty, status, created_at, started_at, finished_at,
    rows_extracted, rows_inserted, rows_updated, rows_deleted, error_message,
    passport, data_source, data_source_url, dsa_table_name, data_table_name,
    load_type, loaded_by
)
SELECT id, entity_name, oid, requested_version, source_version, user_id,
       force_reload, allow_empty, status, created_at, coalesce(started_at, created_at),
       finished_at, rows_received, rows_inserted, rows_updated, rows_deleted,
       error_message, passport, 'minzdrav', 'https://nsi.rosminzdrav.ru/' || oid,
       'dsa_raw_' || entity_name, entity_name, 'full', user_id::text
FROM data.nsi_sync_run;

ALTER TABLE data.nsi_sync_page DROP CONSTRAINT nsi_sync_page_run_id_fkey;
ALTER TABLE data.nsi_sync_page
    ADD CONSTRAINT nsi_sync_page_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES data.dsa_load_batch(run_id);

DROP TABLE data.nsi_sync_run;

CREATE UNIQUE INDEX dsa_load_batch_one_active
    ON data.dsa_load_batch(entity_name)
    WHERE status IN ('queued', 'running');
CREATE INDEX dsa_load_batch_history
    ON data.dsa_load_batch(entity_name, created_at DESC);
