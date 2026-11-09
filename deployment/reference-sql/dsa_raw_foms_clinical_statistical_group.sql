CREATE TABLE data.dsa_raw_foms_clinical_statistical_group (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code varchar(5000),
    care_condition_code varchar(5000),
    valid_from timestamp without time zone,
    name varchar(500),
    cost_coefficient varchar(5000),
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_key jsonb
);
