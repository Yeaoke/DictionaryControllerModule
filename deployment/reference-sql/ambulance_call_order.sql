------------ ambulance_call_order ------------ 1.2.643.5.1.13.13.11.1525
create table if not exists data.ambulance_call_order (
    id                  bigint primary key,    -- Id: идентификатор Минздрава
    name                text not null,         -- Name: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);