------------ foms_consilium_purpose ------------ 1.2.643.5.1.13.13.99.3.55
create table if not exists data.foms_consilium_purpose (
    id                  text not null,               -- ID_CONS: идентификатор цели
    valid_from          timestamp without time zone not null,

    name                text not null,               -- CONS_NAME: наименование цели
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);