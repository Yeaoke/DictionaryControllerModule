------------ measurement_unit ------------ 1.2.643.5.1.13.13.11.1358
create table if not exists data.measurement_unit (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(200) not null,         -- FULLNAME: полное наименование
    short_name          varchar(200),                  -- SHORTNAME: краткое наименование
    print_name          varchar(200),                  -- PRINTNAME: наименование для печати
    measurement         varchar(500),                  -- MEASUREMENT: размерность
    ucum_code           varchar(100),                  -- UCUM: код UCUM

    coefficient         varchar(100),                  -- COEFFICIENT: коэффициент пересчета
    formula             varchar(2000),                  -- FORMULA: формула пересчета
    conversion_unit_id  bigint,                -- CONVERSION_ID: целевая единица пересчета
    conversion_unit_name varchar(200),                 -- CONVERSION_NAME: ее краткое наименование

    okei_code           varchar(100),                  -- OKEI_CODE: код ОКЕИ
    eec_dictionary_code varchar(100),                  -- NSI_CODE_EEC: код справочника ЕАЭК
    eec_element_code    varchar(100),                  -- NSI_ELEMENT_CODE_EEC: код элемента ЕАЭК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);

create index if not exists idx_measurement_unit_conversion_unit_id
    on data.measurement_unit (conversion_unit_id);