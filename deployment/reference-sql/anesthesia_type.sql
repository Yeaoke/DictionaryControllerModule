------------ anesthesia_type ------------ 1.2.643.5.1.13.13.11.1033
create table if not exists data.anesthesia_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- Parent: родительская запись
    name                varchar(200) not null,         -- Name: наименование вида анестезии
    anesthesia_group    varchar(500),                  -- Group: группировочное название
    synonyms            varchar(2000),                  -- Synonym: альтернативные названия
    source_order        varchar(100),                  -- SORT: сортировка из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);

create index if not exists idx_anesthesia_type_parent_id
    on data.anesthesia_type (parent_id);