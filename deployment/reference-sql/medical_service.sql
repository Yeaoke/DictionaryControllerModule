create table if not exists data.medical_service (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    code                varchar(5000) not null,               -- S_CODE: код услуги
    name                varchar(600) not null,               -- NAME: полное название
    relevance           integer
                        check (relevance in (0, 1)),  -- REL: 1 — актуальна, 0 — упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
