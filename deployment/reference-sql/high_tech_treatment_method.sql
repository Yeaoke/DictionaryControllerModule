------------ high_tech_treatment_method ------------ 1.2.643.5.1.13.13.99.2.621
create table if not exists data.high_tech_treatment_method (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                varchar(200) not null,               -- METHOD: метод лечения
    sections            varchar(2000),                        -- RAZDEL: номер/номера разделов ВМП
    implantation_obligation integer,                 -- OBLIGATION: обязательность имплантации
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(100)                         -- Локальные поисковые синонимы
);