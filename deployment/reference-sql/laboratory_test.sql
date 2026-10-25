------------ laboratory_test ------------ 1.2.643.5.1.13.13.11.1080
create table if not exists data.laboratory_test (
    id                  text primary key,      -- ID: уникальный код ФСЛИ
    name                text not null,         -- FULLNAME: полное наименование
    short_name          text,                  -- SHORTNAME: краткое наименование
    english_name        text,                  -- ENGLISHNAME: английское наименование
    synonyms            text,                  -- SYNONYMS: синонимы источника
    loinc_code          text,                  -- LOINC: код LOINC

    analyte             text,                  -- ANALYTE: аналит
    analyte_characteristic text,               -- SPECANALYTE: характеристика аналита
    measurement         text,                  -- MEASUREMENT: размерность
    unit                text,                  -- UNIT: единица измерения
    specimen            text,                  -- SPECIMEN: образец
    time_characteristic text,                  -- TIMECHAR: временная характеристика
    method_type         text,                  -- METHODTYPE: тип метода
    scale_type          text,                  -- SCALETYPE: тип шкалы измерения
    test_status         text,                  -- TESTSTATUS: статус теста
    test_group          text,                  -- GROUP: группа тестов
    nmu_codes           text,                  -- NMU: код или несколько кодов НМУ
    source_order        text,                  -- SORT: код сортировки источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);