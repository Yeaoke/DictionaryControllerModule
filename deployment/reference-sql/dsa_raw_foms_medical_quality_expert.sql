CREATE TABLE data.dsa_raw_foms_medical_quality_expert (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id varchar(5000),
    registry_number varchar(5000),
    legacy_expert_code varchar(5000),
    region_oktmo_code varchar(5000),
    region_name varchar(5000),
    work_phone varchar(5000),
    mobile_phone varchar(5000),
    email varchar(5000),
    registry_created_at timestamp without time zone,
    registry_excluded_at timestamp without time zone,
    exclusion_reason varchar(5000),
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id varchar(5000)
);
