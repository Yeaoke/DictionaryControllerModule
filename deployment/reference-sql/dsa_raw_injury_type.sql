CREATE TABLE data.dsa_raw_injury_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    form_066u_02_code integer,
    form_066u_02_name varchar(5000),
    form_025u_1_code varchar(5000),
    form_025u_1_name varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
