------------ anatomical_location ------------ 1.2.643.5.1.13.13.11.1477
create table if not exists data.anatomical_location (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- ID_PARENT: родительская запись
    name                text not null,         -- NAME: наименование
    english_name        text,                  -- NAME_ENG: английское наименование
    snomed_code         text,                  -- SNOMED_CT: код SNOMED CT
    anatomical_region   text,                  -- ANATOMIC_FIELD: анатомическая область
    laterality          text,                  -- LATERALITY: возможность уточнения стороны
    synonyms            text,                  -- SYNONYMS: синонимы из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_anatomical_location_parent_id
    on data.anatomical_location (parent_id);