------------ foms_control_type ------------ 1.2.643.5.1.13.13.99.3.32
create table if not exists data.foms_control_type (
    id                  bigint not null,             -- IDVID: код вида контроля
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- VIDNAME: наименование вида контроля
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);