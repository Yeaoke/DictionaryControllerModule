------------ bacterium ------------ 1.2.643.5.1.13.13.11.1087
create table if not exists data.bacterium (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- ID_PARENT: родительская запись
    hierarchy_level     integer,               -- LEVEL: уровень иерархии
    name                varchar(200) not null,         -- FULLNAME: полное наименование
    formatted_name      varchar(200),                  -- FORMATNAME: форматированное наименование
    child_count         integer,               -- CHILDCOUNT: число дочерних элементов
    synonyms            varchar(2000),                  -- SYNONIMS: синонимы из источника
    snomed_code         varchar(100),                  -- SNOMED: код SNOMED CT
    ncbi_id             bigint,                -- ID_NCBI: код NCBI
    gram                varchar(100),                  -- GRAM: окраска по Граму
    human               boolean,               -- HUMAN: этиологическая значимость
                                               -- для заболеваний человека

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- SORT: сортировка из источника
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);

create index if not exists idx_bacterium_parent_id
    on data.bacterium (parent_id);