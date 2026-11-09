create table if not exists data.medical_visit_reason (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                varchar(500) not null,         -- NAME: название записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
