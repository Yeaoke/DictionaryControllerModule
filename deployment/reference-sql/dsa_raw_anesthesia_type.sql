CREATE TABLE data.dsa_raw_anesthesia_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    anesthesia_group varchar(5000),
    synonyms varchar(5000),
    source_order varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
