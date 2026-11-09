CREATE TABLE data.dsa_raw_high_tech_treatment_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(1500),
    sections varchar(5000),
    implantation_obligation integer,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
