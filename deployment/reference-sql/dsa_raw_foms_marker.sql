CREATE TABLE data.dsa_raw_foms_marker (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    valid_from timestamp without time zone,
    code varchar(5000),
    name varchar(500),
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_key jsonb
);
