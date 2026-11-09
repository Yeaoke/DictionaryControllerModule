create table if not exists data.foms_clinical_statistical_group (
    code                varchar(5000) not null,               -- K_KSG: номер КСГ
    care_condition_code varchar(5000) not null,               -- IDUMP: код условий оказания МП (V006)
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                varchar(500) not null,               -- N_KSG: наименование КСГ
    cost_coefficient    varchar(5000),                        -- KOEF_Z: коэффициент затратоемкости
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000),                        -- Локальные поисковые синонимы

    primary key (code, care_condition_code, valid_from)
);
