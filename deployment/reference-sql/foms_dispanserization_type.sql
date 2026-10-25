------------ foms_dispanserization_type ------------ 1.2.643.5.1.13.13.99.3.3
create table if not exists data.foms_dispanserization_type (
    id                  text not null,               -- IDDT: код типа диспансеризации
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- DTNAME: наименование типа
    allowed_results     text,                        -- DTRULE: допустимые результаты
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);