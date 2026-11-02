------------ foms_clinical_statistical_group ------------ 1.2.643.5.1.13.13.99.3.5
create table if not exists data.foms_clinical_statistical_group (
    code                varchar(100) not null,               -- K_KSG: номер КСГ
    care_condition_code varchar(100) not null,               -- IDUMP: код условий оказания МП (V006)
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                varchar(200) not null,               -- N_KSG: наименование КСГ
    cost_coefficient    varchar(100),                        -- KOEF_Z: коэффициент затратоемкости
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(100),                        -- Локальные поисковые синонимы

    primary key (code, care_condition_code, valid_from)
);