------------ dispensary_observation_end_reason ------------ 1.2.643.5.1.13.13.11.1045
create table if not exists data.dispensary_observation_end_reason (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- NAME: наименование
    normative_id        bigint not null,       -- NPA: код нормативно-правового акта

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- SORT: сортировка из источника
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_dispensary_observation_end_reason_parent_id
    on data.dispensary_observation_end_reason (parent_id);