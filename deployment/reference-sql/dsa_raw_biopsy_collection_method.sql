CREATE TABLE data.dsa_raw_biopsy_collection_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
