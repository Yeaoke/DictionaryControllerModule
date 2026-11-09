CREATE TABLE data.dsa_raw_implantable_assistive_device_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    rzn_code varchar(5000),
    disease_code varchar(5000),
    actual boolean,
    existence_npa boolean,
    source_order varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
