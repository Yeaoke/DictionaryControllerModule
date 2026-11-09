CREATE TABLE data.dsa_raw_foms_treatment_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
