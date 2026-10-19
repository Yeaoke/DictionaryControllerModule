------------ measurement_unit ------------ 1.2.643.5.1.13.13.11.1358
create table if not exists data.measurement_unit (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- FULLNAME: полное наименование
    short_name          text,                  -- SHORTNAME: краткое наименование
    print_name          text,                  -- PRINTNAME: наименование для печати
    measurement         text,                  -- MEASUREMENT: размерность
    ucum_code           text,                  -- UCUM: код UCUM

    coefficient         text,                  -- COEFFICIENT: коэффициент пересчета
    formula             text,                  -- FORMULA: формула пересчета
    conversion_unit_id  bigint,                -- CONVERSION_ID: целевая единица пересчета
    conversion_unit_name text,                 -- CONVERSION_NAME: ее краткое наименование

    okei_code           text,                  -- OKEI_CODE: код ОКЕИ
    eec_dictionary_code text,                  -- NSI_CODE_EEC: код справочника ЕАЭК
    eec_element_code    text,                  -- NSI_ELEMENT_CODE_EEC: код элемента ЕАЭК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_measurement_unit_conversion_unit_id
    on data.measurement_unit (conversion_unit_id);