CREATE TABLE IF NOT EXISTS data.direction_type (
    id bigint PRIMARY KEY,
    name varchar(500) NOT NULL,
    is_deleted char(1) NOT NULL DEFAULT 'N' CHECK (is_deleted IN ('Y', 'N')),
    display_order numeric(10, 0),
    search_synonym varchar(5000)
);
