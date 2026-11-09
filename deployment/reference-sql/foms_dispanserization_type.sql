create table if not exists data.foms_dispanserization_type (
    id                  varchar(5000) not null,               -- IDDT: код типа диспансеризации
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                varchar(500) not null,               -- DTNAME: наименование типа
    allowed_results     varchar(5000),                        -- DTRULE: допустимые результаты
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000),                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);
