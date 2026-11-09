create table if not exists data.bacterium (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- ID_PARENT: родительская запись
    hierarchy_level     integer,               -- LEVEL: уровень иерархии
    name                varchar(500) not null,         -- FULLNAME: полное наименование
    formatted_name      varchar(5000),                  -- FORMATNAME: форматированное наименование
    child_count         integer,               -- CHILDCOUNT: число дочерних элементов
    synonyms            varchar(5000),                  -- SYNONIMS: синонимы из источника
    snomed_code         varchar(5000),                  -- SNOMED: код SNOMED CT
    ncbi_id             bigint,                -- ID_NCBI: код NCBI
    gram                varchar(5000),                  -- GRAM: окраска по Граму
    human               boolean,               -- HUMAN: этиологическая значимость
                                               -- для заболеваний человека

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- SORT: сортировка из источника
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
