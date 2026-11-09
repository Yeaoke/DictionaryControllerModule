CREATE TABLE data.dsa_raw_measurement_unit (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name varchar(500),
    short_name varchar(5000),
    print_name varchar(5000),
    measurement varchar(5000),
    ucum_code varchar(5000),
    coefficient varchar(5000),
    formula varchar(5000),
    conversion_unit_id bigint,
    conversion_unit_name varchar(5000),
    okei_code varchar(5000),
    eec_dictionary_code varchar(5000),
    eec_element_code varchar(5000),
    display_order numeric(10),
    reject_reason varchar(5000),
    new_id bigint
);
