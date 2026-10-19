------------ medical_specialty ------------ 1.2.643.5.1.13.13.11.1066
create table if not exists data.medical_specialty (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PARENT: родительская запись
    name                text not null,               -- NAME: полное название
    relevance           integer,                     -- REL: 0 — специальность упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения
    ffoms_code          integer,                     -- IDSPEC: код ФФОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_medical_specialty_parent_id
    on data.medical_specialty (parent_id);