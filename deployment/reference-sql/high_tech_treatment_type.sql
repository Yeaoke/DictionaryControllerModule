create table if not exists data.high_tech_treatment_type (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                varchar(500) not null,               -- TREATMENT: вид лечения
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
