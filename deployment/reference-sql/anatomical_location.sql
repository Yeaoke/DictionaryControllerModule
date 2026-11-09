create table if not exists data.anatomical_location (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- ID_PARENT: родительская запись
    name                varchar(500) not null,         -- NAME: наименование
    english_name        varchar(5000),                  -- NAME_ENG: английское наименование
    snomed_code         varchar(5000),                  -- SNOMED_CT: код SNOMED CT
    anatomical_region   varchar(5000),                  -- ANATOMIC_FIELD: анатомическая область
    laterality          varchar(5000),                  -- LATERALITY: возможность уточнения стороны
    synonyms            varchar(5000),                  -- SYNONYMS: синонимы из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
