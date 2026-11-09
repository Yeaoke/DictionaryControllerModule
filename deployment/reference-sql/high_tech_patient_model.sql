create table if not exists data.high_tech_patient_model (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                varchar(1600) not null,               -- MODEL: модель пациента
    sections            varchar(5000),                        -- RAZDEL: номер/номера разделов ВМП
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
