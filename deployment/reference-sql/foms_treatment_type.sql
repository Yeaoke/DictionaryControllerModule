create table if not exists data.foms_treatment_type (
    id                  bigint primary key,          -- ID_TLech: идентификатор типа лечения
    name                varchar(500) not null,               -- TLech_NAME: наименование типа лечения
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
