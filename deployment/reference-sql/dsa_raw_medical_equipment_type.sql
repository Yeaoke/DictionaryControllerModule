CREATE TABLE data.dsa_raw_medical_equipment_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    available integer,
    abolished_at timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
