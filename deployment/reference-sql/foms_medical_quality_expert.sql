create table if not exists data.foms_medical_quality_expert (
    id                  varchar(5000) primary key,            -- UIDEKMP: уникальный номер эксперта
    registry_number     varchar(5000),                        -- IDEKMP: реестровый номер записи
    legacy_expert_code  varchar(5000),                        -- N_EXPERT: код до 01.09.2021

    region_oktmo_code   varchar(5000),                        -- OKTMO_P: код территории субъекта РФ
    region_name         varchar(5000),                        -- SUBJ: наименование субъекта РФ
    work_phone          varchar(5000),                        -- WORKPHONE: рабочий телефон
    mobile_phone        varchar(5000),                        -- MOBILEPHONE: мобильный телефон
    email               varchar(5000),                        -- EMAIL: электронная почта

    registry_created_at timestamp without time zone, -- D_BEGIN: создание записи в реестре
    registry_excluded_at timestamp without time zone,-- D_END: исключение из реестра
    exclusion_reason    varchar(5000),                        -- NAME_E: причина исключения

    valid_from          timestamp without time zone, -- DATEBEG: начало действия записи
    valid_to            timestamp without time zone, -- DATEEND: окончание действия записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
