create table if not exists data.laboratory_test (
    id                  varchar(5000) primary key,      -- ID: уникальный код ФСЛИ
    name                varchar(500) not null,         -- FULLNAME: полное наименование
    short_name          varchar(5000),                  -- SHORTNAME: краткое наименование
    english_name        varchar(5000),                  -- ENGLISHNAME: английское наименование
    synonyms            varchar(5000),                  -- SYNONYMS: синонимы источника
    loinc_code          varchar(5000),                  -- LOINC: код LOINC

    analyte             varchar(5000),                  -- ANALYTE: аналит
    analyte_characteristic varchar(5000),               -- SPECANALYTE: характеристика аналита
    measurement         varchar(5000),                  -- MEASUREMENT: размерность
    unit                varchar(5000),                  -- UNIT: единица измерения
    specimen            varchar(5000),                  -- SPECIMEN: образец
    time_characteristic varchar(5000),                  -- TIMECHAR: временная характеристика
    method_type         varchar(5000),                  -- METHODTYPE: тип метода
    scale_type          varchar(5000),                  -- SCALETYPE: тип шкалы измерения
    test_status         varchar(5000),                  -- TESTSTATUS: статус теста
    test_group          varchar(5000),                  -- GROUP: группа тестов
    nmu_codes           varchar(5000),                  -- NMU: код или несколько кодов НМУ
    source_order        varchar(5000),                  -- SORT: код сортировки источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
