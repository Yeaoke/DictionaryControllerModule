CREATE TABLE data.dsa_raw_medical_care_location (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    form_025_1y_flag integer,
    oms_visit_place_code integer,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
