------------ biopsy_complexity_category ------------ 1.2.643.5.1.13.13.11.1549
create table if not exists data.biopsy_complexity_category (
    id                  bigint primary key,    -- Id: идентификатор Минздрава
    name                text not null,         -- Name: наименование
    description         text,                  -- Description: описание категории

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);