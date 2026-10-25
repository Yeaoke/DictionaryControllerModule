ALTER TABLE data.dsa_load_batch ALTER COLUMN status TYPE varchar(20);

ALTER TABLE data.dsa_loaded_version
    ADD COLUMN IF NOT EXISTS data_source varchar(10),
    ADD COLUMN IF NOT EXISTS data_source_url varchar(500),
    ADD COLUMN IF NOT EXISTS load_date timestamp with time zone;

-- Match the supplied bigserial staging ID; explicit NSI IDs are still accepted.
CREATE SEQUENCE IF NOT EXISTS data.dsa_raw_direction_type_id_seq AS bigint;
ALTER SEQUENCE data.dsa_raw_direction_type_id_seq OWNED BY data.dsa_raw_direction_type.id;
ALTER TABLE data.dsa_raw_direction_type
    ALTER COLUMN id SET DEFAULT nextval('data.dsa_raw_direction_type_id_seq');
SELECT setval(
    'data.dsa_raw_direction_type_id_seq',
    greatest(coalesce(max(id), 1), (SELECT last_value FROM data.dsa_raw_direction_type_id_seq)),
    count(*) > 0 OR (SELECT is_called FROM data.dsa_raw_direction_type_id_seq)
) FROM data.dsa_raw_direction_type;
