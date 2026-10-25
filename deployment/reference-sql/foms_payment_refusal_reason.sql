------------ foms_payment_refusal_reason ------------ 1.2.643.5.1.13.13.99.3.11
create table if not exists data.foms_payment_refusal_reason (
    code                bigint not null,             -- Kod: код ошибки
    name                text not null,               -- Naim: наименование причины отказа
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    refusal_basis       text,                        -- Osn: основание отказа
    service_comment     text,                        -- Komment: служебный комментарий
    control_type_code   integer,                     -- IDVID: код вида контроля, резерв
    penalty_coefficient text,                        -- K_SH: коэффициент штрафа
    nonpayment_coefficient text,                     -- K_NO: коэффициент неоплаты
    form_pg_code        text,                        -- KodPG: код по форме № ПГ
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (code, name, valid_from)
);