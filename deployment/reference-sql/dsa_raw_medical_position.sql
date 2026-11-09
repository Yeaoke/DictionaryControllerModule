CREATE TABLE data.dsa_raw_medical_position (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name varchar(500),
    equivalent varchar(5000),
    display_order numeric(10),
    normative_id bigint,
    group_flag integer,
    form_30 integer,
    actual integer,
    end_date timestamp without time zone,
    comment varchar(5000),
    need_qual integer,
    zs integer,
    need_cert integer,
    reject_reason varchar(5000),
    new_id bigint
);
