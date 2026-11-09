CREATE TABLE data.dsa_raw_foms_drug_therapy_medication (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id varchar(5000),
    valid_from timestamp without time zone,
    name varchar(700),
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_key jsonb
);
