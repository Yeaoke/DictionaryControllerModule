------------ disease_outcome ------------ 1.2.643.5.1.13.13.11.1491
create table if not exists data.disease_outcome (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                varchar(200) not null,         -- NAME: наименование исхода
    oms_outcome_code    varchar(100),                  -- IDIZ: код для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);