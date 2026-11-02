------------ laboratory_test ------------ 1.2.643.5.1.13.13.11.1080
create table if not exists data.laboratory_test (
    id                  varchar(100) primary key,      -- ID: уникальный код ФСЛИ
    name                varchar(200) not null,         -- FULLNAME: полное наименование
    short_name          varchar(200),                  -- SHORTNAME: краткое наименование
    english_name        varchar(200),                  -- ENGLISHNAME: английское наименование
    synonyms            varchar(2000),                  -- SYNONYMS: синонимы источника
    loinc_code          varchar(100),                  -- LOINC: код LOINC

    analyte             varchar(500),                  -- ANALYTE: аналит
    analyte_characteristic varchar(500),               -- SPECANALYTE: характеристика аналита
    measurement         varchar(500),                  -- MEASUREMENT: размерность
    unit                varchar(100),                  -- UNIT: единица измерения
    specimen            varchar(500),                  -- SPECIMEN: образец
    time_characteristic varchar(100),                  -- TIMECHAR: временная характеристика
    method_type         varchar(500),                  -- METHODTYPE: тип метода
    scale_type          varchar(100),                  -- SCALETYPE: тип шкалы измерения
    test_status         varchar(100),                  -- TESTSTATUS: статус теста
    test_group          varchar(500),                  -- GROUP: группа тестов
    nmu_codes           varchar(2000),                  -- NMU: код или несколько кодов НМУ
    source_order        varchar(100),                  -- SORT: код сортировки источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);