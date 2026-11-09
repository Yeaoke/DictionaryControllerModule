CREATE TABLE data.dsa_raw_laboratory_specimen (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    specimen_group varchar(5000),
    material_id bigint,
    material_name varchar(5000),
    name varchar(500),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
