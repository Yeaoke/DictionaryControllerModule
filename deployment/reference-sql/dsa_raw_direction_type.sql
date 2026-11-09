CREATE TABLE IF NOT EXISTS data.dsa_raw_direction_type (
    id bigint PRIMARY KEY,
    name varchar(500) NOT NULL,
    doc varchar(5000),
    sort numeric(10, 0),
    reject_reason varchar(5000),
    new_id bigint
);
