create table if not exists data.medical_care_location (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(500) not null,         -- NAME: полное название
    form_025_1y_flag     integer,               -- F025-1y: 1 — используется в талоне
    oms_visit_place_code integer,              -- ID_MOP: код места обращения для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10) not null,  -- SORT: обязательный код сортировки
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
