CREATE TABLE data.dsa_raw_bed_profile (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    age_group integer,
    relevance integer,
    abolished_at timestamp without time zone,
    form_30_code varchar(5000),
    section_code varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
