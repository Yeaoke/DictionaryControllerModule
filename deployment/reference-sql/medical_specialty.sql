create table if not exists data.medical_specialty (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PARENT: родительская запись
    name                varchar(500) not null,               -- NAME: полное название
    relevance           integer,                     -- REL: 0 — специальность упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения
    ffoms_code          integer,                     -- IDSPEC: код ФФОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
