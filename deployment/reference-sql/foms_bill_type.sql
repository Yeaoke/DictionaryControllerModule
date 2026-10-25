------------ foms_bill_type ------------ 1.2.643.5.1.13.13.99.3.42
create table if not exists data.foms_bill_type (
    code                text not null,               -- billcod: код типа счета
    region_okato_code   text not null,               -- tf_okato: код субъекта РФ по ОКАТО
    name                text not null,               -- bill_namp: полное наименование
    short_name          text,                        -- bill_namk: краткое наименование
    payer_org_type      text,                        -- orgType: тип организации-плательщика
    funding_source      text
                        check (funding_source in ('0', '1')),
                                                     -- IS_PAY: 1 — ОМС, 0 — бюджет субъекта
    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (code, region_okato_code)
);