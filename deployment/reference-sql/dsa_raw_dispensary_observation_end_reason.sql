CREATE TABLE data.dsa_raw_dispensary_observation_end_reason (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    normative_id bigint,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
