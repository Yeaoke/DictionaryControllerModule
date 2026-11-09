CREATE TABLE data.dsa_raw_medical_care_condition (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    oms_condition_code integer,
    comments varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
