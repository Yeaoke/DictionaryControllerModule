------------ foms_histological_sign ------------ 1.2.643.5.1.13.13.99.3.51
create table if not exists data.foms_histological_sign (
    id                  bigint primary key,          -- ID_Mrf: идентификатор признака
    name                text not null,               -- Mrf_NAME: наименование признака
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);