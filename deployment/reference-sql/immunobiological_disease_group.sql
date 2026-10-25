------------ immunobiological_disease_group ------------ 1.2.643.5.1.13.13.99.2.1111
create table if not exists data.immunobiological_disease_group (
    id                  bigint primary key,    -- id: идентификатор Минздрава
    name                text not null,         -- NAME: наименование
    synonyms            text,                  -- SYNONYMS: синонимы из источника
    used_in_elmk        boolean,               -- EPMB: использование в ЭЛМК
    elmk_name           text,                  -- NAME_EPMB: наименование в ЭЛМК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);