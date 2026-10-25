------------ medical_visit_reason ------------ 1.2.643.5.1.13.13.99.2.443
create table if not exists data.medical_visit_reason (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                text not null,         -- NAME: название записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);