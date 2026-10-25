------------ laterality ------------ 1.2.643.5.1.13.13.99.2.778
create table if not exists data.laterality (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- laterality: наименование стороны

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);