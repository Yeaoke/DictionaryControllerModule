create table if not exists data.immunobiological_disease_group (
    id                  bigint primary key,    -- id: идентификатор Минздрава
    name                varchar(500) not null,         -- NAME: наименование
    synonyms            varchar(5000),                  -- SYNONYMS: синонимы из источника
    used_in_elmk        boolean,               -- EPMB: использование в ЭЛМК
    elmk_name           varchar(5000),                  -- NAME_EPMB: наименование в ЭЛМК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
