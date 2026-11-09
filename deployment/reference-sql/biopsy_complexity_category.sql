create table if not exists data.biopsy_complexity_category (
    id                  bigint primary key,    -- Id: идентификатор Минздрава
    name                varchar(500) not null,         -- Name: наименование
    description         varchar(5000),                  -- Description: описание категории

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
