CREATE TABLE data.dsa_raw_medical_care_form (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    oms_care_form_code integer,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
