CREATE TABLE data.dsa_raw_foms_payment_organization (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id varchar(5000),
    name varchar(500),
    short_name varchar(5000),
    organization_type varchar(5000),
    territorial_fund_code varchar(5000),
    smo_code varchar(5000),
    region_okato_code varchar(5000),
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id varchar(5000)
);
