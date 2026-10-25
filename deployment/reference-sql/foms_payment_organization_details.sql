------------ foms_payment_organization_details ------------ 1.2.643.5.1.13.13.99.3.43
create table if not exists data.foms_payment_organization_details (
    bill_type_code      text not null,               -- billcod: код типа счета
    organization_code   bigint not null,             -- orgcod: номер организации
    region_okato_code   text not null,               -- tf_okato: код субъекта РФ
    source_record_id    bigint,                      -- idzap: идентификатор записи

    inn                 text,                        -- inn
    kpp                 text,                        -- kpp
    account_type        text
                        check (account_type in ('1', '2')),
                                                     -- accounttype: 1 — банковский,
                                                     -- 2 — казначейский счет
    account_number      text,                        -- accountnum: номер счета
    correspondent_account text,                      -- corraccount: корреспондентский счет
    bank_name           text,                        -- bankname: наименование банка
    bank_bik            text,                        -- bankbik: БИК банка

    tofk_code           text,                        -- tofk_code: код ТОФК
    tofk_name           text,                        -- tofk_name: наименование ТОФК
    tofk_bik            text,                        -- tofk_bik: БИК ТОФК
    treasury_single_account text,                    -- sta_character: ЕКС
    financial_agency_name text,                      -- name_agency: финансовый орган

    personal_account    text,                        -- personal_account: лицевой счет
    personal_account_purpose text,                   -- function_personal_account
    personal_account_tofk_code text,                 -- code_tofk: код ТОФК по лицевому счету

    income_admin_name   text,                        -- name_income_admin
    income_admin_inn    text,                        -- inn_income_admin
    income_admin_kpp    text,                        -- kpp_income_admin
    personal_account_income_admin boolean,           -- Тип BOOLEAN указан в паспорте

    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (bill_type_code, organization_code, region_okato_code)
);