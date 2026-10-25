------------ disability_group ------------ 1.2.643.5.1.13.13.11.1053
create table if not exists data.disability_group (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название
    snomed_code         text,                  -- SCTID: код SNOMED CT

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);