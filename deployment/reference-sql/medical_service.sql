------------ medical_service ------------ 1.2.643.5.1.13.13.11.1070
create table if not exists data.medical_service (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    code                text not null,               -- S_CODE: код услуги
    name                text not null,               -- NAME: полное название
    relevance           integer
                        check (relevance in (0, 1)),  -- REL: 1 — актуальна, 0 — упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_medical_service_code
    on data.medical_service (code);