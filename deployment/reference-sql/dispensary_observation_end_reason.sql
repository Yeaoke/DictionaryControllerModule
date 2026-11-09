create table if not exists data.dispensary_observation_end_reason (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                varchar(500) not null,         -- NAME: наименование
    normative_id        bigint not null,       -- NPA: код нормативно-правового акта

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- SORT: сортировка из источника
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
