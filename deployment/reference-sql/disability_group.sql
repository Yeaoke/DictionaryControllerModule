create table if not exists data.disability_group (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(500) not null,         -- NAME: полное название
    snomed_code         varchar(5000),                  -- SCTID: код SNOMED CT

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
