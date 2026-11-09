create table if not exists data.foms_bill_type (
    code                varchar(5000) not null,               -- billcod: код типа счета
    region_okato_code   varchar(5000) not null,               -- tf_okato: код субъекта РФ по ОКАТО
    name                varchar(500) not null,               -- bill_namp: полное наименование
    short_name          varchar(5000),                        -- bill_namk: краткое наименование
    payer_org_type      varchar(5000),                        -- orgType: тип организации-плательщика
    funding_source      varchar(5000)
                        check (funding_source in ('0', '1')),
                                                     -- IS_PAY: 1 — ОМС, 0 — бюджет субъекта
    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000),                        -- Локальные поисковые синонимы

    primary key (code, region_okato_code)
);
