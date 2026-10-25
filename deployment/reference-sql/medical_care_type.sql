------------ medical_care_type ------------ 1.2.643.5.1.13.13.11.1034
create table if not exists data.medical_care_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT: родительская запись
    name                text not null,         -- NAME: полное название
    oms_care_type_code  integer,               -- IDVMP: код вида медицинской помощи для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10) not null,  -- SORT: обязательный код сортировки
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_medical_care_type_parent_id
    on data.medical_care_type (parent_id);