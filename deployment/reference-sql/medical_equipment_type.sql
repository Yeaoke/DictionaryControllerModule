create table if not exists data.medical_equipment_type (
    id                  bigint primary key,          -- id: идентификатор Минздрава
    parent_id           bigint,                      -- parent_id: родительская запись
    name                varchar(500) not null,               -- equipment_type: наименование
    available           integer
                        check (available in (0, 1)), -- available: доступность для выбора
    abolished_at        timestamp without time zone, -- date_end: дата упразднения

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
