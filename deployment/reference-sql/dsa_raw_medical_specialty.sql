CREATE TABLE data.dsa_raw_medical_specialty (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    relevance integer,
    abolished_at timestamp without time zone,
    ffoms_code integer,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
