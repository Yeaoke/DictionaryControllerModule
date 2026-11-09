CREATE TABLE data.dsa_raw_immunobiological_disease_group (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    synonyms varchar(5000),
    used_in_elmk boolean,
    elmk_name varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
