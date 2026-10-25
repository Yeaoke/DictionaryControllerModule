------------ medical_care_form ------------ 1.2.643.5.1.13.13.11.1551
create table if not exists data.medical_care_form (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- S_NAME: наименование формы
    oms_care_form_code  integer,               -- IDFRMMP: код формы оказания МП для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);