------------ high_tech_patient_model ------------ 1.2.643.5.1.13.13.99.2.360
create table if not exists data.high_tech_patient_model (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                text not null,               -- MODEL: модель пациента
    sections            text,                        -- RAZDEL: номер/номера разделов ВМП
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);