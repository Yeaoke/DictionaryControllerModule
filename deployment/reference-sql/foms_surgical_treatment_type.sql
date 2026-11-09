create table if not exists data.foms_surgical_treatment_type (
    id                  bigint primary key,          -- ID_THir: идентификатор типа лечения
    name                varchar(500) not null,               -- THir_NAME: наименование
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
