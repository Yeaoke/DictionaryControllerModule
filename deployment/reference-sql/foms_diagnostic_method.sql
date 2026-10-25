------------ foms_diagnostic_method ------------ 1.2.643.5.1.13.13.99.3.47
create table if not exists data.foms_diagnostic_method (
    id                  bigint primary key,          -- IDMET: код метода
    name                text not null,               -- N_MET: наименование метода
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);