------------ foms_medical_quality_expert ------------ 1.2.643.5.1.13.13.99.3.41
create table if not exists data.foms_medical_quality_expert (
    id                  text primary key,            -- UIDEKMP: уникальный номер эксперта
    registry_number     text,                        -- IDEKMP: реестровый номер записи
    legacy_expert_code  text,                        -- N_EXPERT: код до 01.09.2021

    region_oktmo_code   text,                        -- OKTMO_P: код территории субъекта РФ
    region_name         text,                        -- SUBJ: наименование субъекта РФ
    work_phone          text,                        -- WORKPHONE: рабочий телефон
    mobile_phone        text,                        -- MOBILEPHONE: мобильный телефон
    email               text,                        -- EMAIL: электронная почта

    registry_created_at timestamp without time zone, -- D_BEGIN: создание записи в реестре
    registry_excluded_at timestamp without time zone,-- D_END: исключение из реестра
    exclusion_reason    text,                        -- NAME_E: причина исключения

    valid_from          timestamp without time zone, -- DATEBEG: начало действия записи
    valid_to            timestamp without time zone, -- DATEEND: окончание действия записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_foms_medical_quality_expert_registry_number
    on data.foms_medical_quality_expert (registry_number);