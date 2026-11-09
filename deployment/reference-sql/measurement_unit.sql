create table if not exists data.measurement_unit (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(500) not null,         -- FULLNAME: полное наименование
    short_name          varchar(5000),                  -- SHORTNAME: краткое наименование
    print_name          varchar(5000),                  -- PRINTNAME: наименование для печати
    measurement         varchar(5000),                  -- MEASUREMENT: размерность
    ucum_code           varchar(5000),                  -- UCUM: код UCUM

    coefficient         varchar(5000),                  -- COEFFICIENT: коэффициент пересчета
    formula             varchar(5000),                  -- FORMULA: формула пересчета
    conversion_unit_id  bigint,                -- CONVERSION_ID: целевая единица пересчета
    conversion_unit_name varchar(5000),                 -- CONVERSION_NAME: ее краткое наименование

    okei_code           varchar(5000),                  -- OKEI_CODE: код ОКЕИ
    eec_dictionary_code varchar(5000),                  -- NSI_CODE_EEC: код справочника ЕАЭК
    eec_element_code    varchar(5000),                  -- NSI_ELEMENT_CODE_EEC: код элемента ЕАЭК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
