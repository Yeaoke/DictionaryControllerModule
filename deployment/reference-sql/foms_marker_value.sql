------------ foms_marker_value ------------ 1.2.643.5.1.13.13.99.3.60
create table if not exists data.foms_marker_value (
    id                  bigint not null,             -- ID_R_I: идентификатор записи
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    code                text,                        -- KOD_R_I: обозначение результата
    name                text not null,               -- R_I_NAME: наименование результата
    marker_id           bigint,                      -- ID_Igh: идентификатор маркера N010
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

create index if not exists idx_foms_marker_value_marker_id
    on data.foms_marker_value (marker_id);