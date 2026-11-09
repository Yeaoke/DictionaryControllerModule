CREATE TABLE data.dsa_raw_bacterium (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    hierarchy_level integer,
    name varchar(500),
    formatted_name varchar(5000),
    child_count integer,
    synonyms varchar(5000),
    snomed_code varchar(5000),
    ncbi_id bigint,
    gram varchar(5000),
    human boolean,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
