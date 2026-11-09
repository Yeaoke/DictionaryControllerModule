create table if not exists data.anesthesia_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- Parent: родительская запись
    name                varchar(500) not null,         -- Name: наименование вида анестезии
    anesthesia_group    varchar(5000),                  -- Group: группировочное название
    synonyms            varchar(5000),                  -- Synonym: альтернативные названия
    source_order        varchar(5000),                  -- SORT: сортировка из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
