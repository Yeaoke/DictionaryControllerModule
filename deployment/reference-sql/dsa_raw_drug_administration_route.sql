CREATE TABLE data.dsa_raw_drug_administration_route (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    english_name varchar(5000),
    eec_dictionary_code varchar(5000),
    eec_element_code varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
