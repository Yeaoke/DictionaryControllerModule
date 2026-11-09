create table if not exists data.foms_payment_organization_details (
    bill_type_code      varchar(5000) not null,               -- billcod: код типа счета
    organization_code   bigint not null,             -- orgcod: номер организации
    region_okato_code   varchar(5000) not null,               -- tf_okato: код субъекта РФ
    source_record_id    bigint,                      -- idzap: идентификатор записи

    inn                 varchar(5000),                        -- inn
    kpp                 varchar(5000),                        -- kpp
    account_type        varchar(5000)
                        check (account_type in ('1', '2')),
                                                     -- accounttype: 1 — банковский,
                                                     -- 2 — казначейский счет
    account_number      varchar(5000),                        -- accountnum: номер счета
    correspondent_account varchar(5000),                      -- corraccount: корреспондентский счет
    bank_name           varchar(5000),                        -- bankname: наименование банка
    bank_bik            varchar(5000),                        -- bankbik: БИК банка

    tofk_code           varchar(5000),                        -- tofk_code: код ТОФК
    tofk_name           varchar(5000),                        -- tofk_name: наименование ТОФК
    tofk_bik            varchar(5000),                        -- tofk_bik: БИК ТОФК
    treasury_single_account varchar(5000),                    -- sta_character: ЕКС
    financial_agency_name varchar(5000),                      -- name_agency: финансовый орган

    personal_account    varchar(5000),                        -- personal_account: лицевой счет
    personal_account_purpose varchar(5000),                   -- function_personal_account
    personal_account_tofk_code varchar(5000),                 -- code_tofk: код ТОФК по лицевому счету

    income_admin_name   varchar(5000),                        -- name_income_admin
    income_admin_inn    varchar(5000),                        -- inn_income_admin
    income_admin_kpp    varchar(5000),                        -- kpp_income_admin
    personal_account_income_admin boolean,           -- Тип BOOLEAN указан в паспорте

    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000),                        -- Локальные поисковые синонимы

    primary key (bill_type_code, organization_code, region_okato_code)
);
