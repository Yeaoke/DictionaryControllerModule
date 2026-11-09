create table if not exists data.foms_diagnostic_method (
    id                  bigint primary key,          -- IDMET: код метода
    name                varchar(500) not null,               -- N_MET: наименование метода
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
