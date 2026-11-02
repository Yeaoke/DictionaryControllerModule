------------ foms_marker ------------ 1.2.643.5.1.13.13.99.3.59
create table if not exists data.foms_marker (
    id                  bigint not null,             -- ID_Igh: идентификатор маркера
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    code                varchar(100),                        -- KOD_Igh: обозначение маркера
    name                varchar(200) not null,               -- Igh_NAME: наименование маркера
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(100),                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);