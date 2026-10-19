------------ ambulance_team_type ------------ 1.2.643.5.1.13.13.99.2.1076
create table if not exists data.ambulance_team_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- NAME: наименование
    form_30_code        text,                  -- FORM_30: код строки формы № 30

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_ambulance_team_type_parent_id
    on data.ambulance_team_type (parent_id);