CREATE TABLE data.dsa_raw_icd10 (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    code varchar(5000),
    name varchar(500),
    rec_code varchar(5000),
    additional_code integer,
    actual integer,
    actuality_changed_at timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
