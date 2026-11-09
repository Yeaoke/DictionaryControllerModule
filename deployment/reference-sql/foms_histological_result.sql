create table if not exists data.foms_histological_result (
    id                  bigint primary key,          -- ID_R_M: идентификатор записи
    histological_sign_code varchar(5000),                     -- ID_Mrf: идентификатор признака N007
    name                varchar(500) not null,               -- R_M_NAME: наименование результата
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
