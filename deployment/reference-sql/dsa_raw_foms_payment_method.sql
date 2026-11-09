CREATE TABLE data.dsa_raw_foms_payment_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    valid_from timestamp without time zone,
    name varchar(500),
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_key jsonb
);
