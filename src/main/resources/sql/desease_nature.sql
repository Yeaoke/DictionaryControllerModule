------------ disease_nature ------------ 1.2.643.5.1.13.13.11.1049
create table if not exists data.disease_nature (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: наименование
    form_025_1u_code     integer,               -- F_025-1u: код формы № 025-1/у

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);