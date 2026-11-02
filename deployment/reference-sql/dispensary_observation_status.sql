------------ dispensary_observation_status ------------ 1.2.643.5.1.13.13.11.1047
create table if not exists data.dispensary_observation_status (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(200) not null,         -- NAME: полное название

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);