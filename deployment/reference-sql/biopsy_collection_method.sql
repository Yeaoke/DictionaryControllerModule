------------ biopsy_collection_method ------------ 1.2.643.5.1.13.13.99.2.33
create table if not exists data.biopsy_collection_method (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(200) not null,         -- NAME: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);