------------ disease_outcome ------------ 1.2.643.5.1.13.13.11.1491
create table if not exists data.disease_outcome (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                text not null,         -- NAME: наименование исхода
    oms_outcome_code    text,                  -- IDIZ: код для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);