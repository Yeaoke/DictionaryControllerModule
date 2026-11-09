CREATE TABLE data.dsa_raw_anatomical_location (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    english_name varchar(5000),
    snomed_code varchar(5000),
    anatomical_region varchar(5000),
    laterality varchar(5000),
    synonyms varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
