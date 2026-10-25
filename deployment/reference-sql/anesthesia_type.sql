------------ anesthesia_type ------------ 1.2.643.5.1.13.13.11.1033
create table if not exists data.anesthesia_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- Parent: родительская запись
    name                text not null,         -- Name: наименование вида анестезии
    anesthesia_group    text,                  -- Group: группировочное название
    synonyms            text,                  -- Synonym: альтернативные названия
    source_order        text,                  -- SORT: сортировка из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_anesthesia_type_parent_id
    on data.anesthesia_type (parent_id);