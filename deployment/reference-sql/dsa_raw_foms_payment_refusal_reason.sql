CREATE TABLE data.dsa_raw_foms_payment_refusal_reason (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code bigint,
    name varchar(1200),
    valid_from timestamp without time zone,
    refusal_basis varchar(5000),
    service_comment varchar(5000),
    control_type_code integer,
    penalty_coefficient varchar(5000),
    nonpayment_coefficient varchar(5000),
    form_pg_code varchar(5000),
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_key jsonb
);
