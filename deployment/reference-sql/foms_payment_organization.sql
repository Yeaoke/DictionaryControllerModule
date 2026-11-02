------------ foms_payment_organization ------------ 1.2.643.5.1.13.13.99.3.1
create table if not exists data.foms_payment_organization (
    id                  varchar(100) primary key,            -- orgcod: номер организации
    name                varchar(200) not null,               -- nam_orgp: полное наименование
    short_name          varchar(200),                        -- nam_orgk: краткое наименование
    organization_type   varchar(100)
                        check (organization_type in ('0', '1', '2')),
                                                     -- orgtype: 0 — ФОМС,
                                                     -- 1 — ТФОМС, 2 — СМО
    territorial_fund_code varchar(100),                      -- tf_kod: код ТФОМС
    smo_code            varchar(100),                        -- smocod: код СМО
    region_okato_code   varchar(100),                        -- tf_okato: код субъекта РФ по ОКАТО
    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(100)                         -- Локальные поисковые синонимы
);