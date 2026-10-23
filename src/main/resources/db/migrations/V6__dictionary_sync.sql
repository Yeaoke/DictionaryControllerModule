-- V1-V5 remain immutable. Generic sync stores complete source payloads and audit history.
CREATE TABLE data.nsi_sync_run (
    id uuid PRIMARY KEY,
    entity_name varchar(100) NOT NULL,
    oid text NOT NULL,
    requested_version text,
    source_version text,
    user_id bigint NOT NULL,
    force_reload boolean NOT NULL DEFAULT false,
    allow_empty boolean NOT NULL DEFAULT false,
    status text NOT NULL CHECK (status IN ('queued','running','success','skipped','failed','interrupted')),
    created_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    finished_at timestamptz,
    rows_received bigint NOT NULL DEFAULT 0,
    rows_inserted bigint NOT NULL DEFAULT 0,
    rows_updated bigint NOT NULL DEFAULT 0,
    rows_deleted bigint NOT NULL DEFAULT 0,
    passport jsonb,
    error_message text
);
CREATE UNIQUE INDEX nsi_sync_one_active ON data.nsi_sync_run(entity_name)
    WHERE status IN ('queued','running');
CREATE INDEX nsi_sync_run_history ON data.nsi_sync_run(entity_name, created_at DESC);
CREATE TABLE data.nsi_sync_page (
    run_id uuid NOT NULL REFERENCES data.nsi_sync_run(id),
    kind text NOT NULL CHECK (kind IN ('data','versions')),
    page_number integer NOT NULL,
    payload jsonb NOT NULL,
    PRIMARY KEY(run_id, kind, page_number)
);
CREATE TABLE data.nsi_dictionary_passport (
    entity_name varchar(100) NOT NULL,
    version text NOT NULL,
    payload jsonb NOT NULL,
    fetched_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(entity_name, version)
);
CREATE TABLE data.nsi_dictionary_version (
    entity_name varchar(100) NOT NULL,
    version text NOT NULL,
    payload jsonb NOT NULL,
    fetched_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(entity_name, version)
);
-- Preserve DOC in both the typed target and source staging.
ALTER TABLE data.direction_type ADD COLUMN doc text;
ALTER TABLE data.direction_type ALTER COLUMN name TYPE text;
ALTER TABLE data.dsa_raw_direction_type ALTER COLUMN name TYPE text;
ALTER TABLE data.dsa_raw_direction_type ALTER COLUMN doc TYPE text;
-- Compatibility with the existing Java service: return the precise batch id.
-- The legacy procedure still requires host-system logging tables (see V4).
ALTER PROCEDURE dsa_data_load.load_direction_type(bigint, varchar, varchar)
    RENAME TO load_direction_type_legacy;
CREATE PROCEDURE dsa_data_load.load_direction_type(
    IN p_user_id bigint, IN p_version varchar, IN p_source_url varchar,
    OUT p_batch_id bigint
)
LANGUAGE plpgsql AS $$
BEGIN
    CALL dsa_data_load.load_direction_type_legacy(p_user_id, p_version, p_source_url);
    -- V4 owns a transaction-level dictionary lock, so no competing batch can intervene.
    SELECT id INTO STRICT p_batch_id FROM data.dsa_load_batch
    WHERE entity_name = 'direction_type' ORDER BY id DESC LIMIT 1;
END;
$$;
