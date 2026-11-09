CREATE TABLE data.dsa_raw_clinical_scale_parameter (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(1000),
    vital_parameter_id bigint,
    point varchar(5000),
    interpretation_group_code bigint,
    grouping_scale integer,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
