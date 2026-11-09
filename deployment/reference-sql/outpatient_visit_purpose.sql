create table if not exists data.outpatient_visit_purpose (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(500) not null,         -- S_NAME: наименование
    invisible           integer,               -- INVISIBLE: признак невидимости

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
