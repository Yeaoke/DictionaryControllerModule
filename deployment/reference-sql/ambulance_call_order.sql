create table if not exists data.ambulance_call_order (
    id                  bigint primary key,    -- Id: идентификатор Минздрава
    name                varchar(500) not null,         -- Name: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
