------------ high_tech_medical_care_type ------------ 1.2.643.5.1.13.13.11.1493
create table if not exists data.high_tech_medical_care_type (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                text not null,               -- NAME: наименование вида ВМП
    name_id             bigint,                      -- ID_NAME: код наименования вида ВМП

    profile_id          bigint,                      -- ID_PROFILE: код профиля ВМП
    profile_name        text,                        -- PROFILE: профиль медицинской помощи
    icd10_code          text,                        -- ICD_10: код МКБ-10

    patient_model_id    bigint,                      -- ID_MODEL: код модели пациента
    patient_model       text,                        -- MODEL: модель пациента
    treatment_type_id   bigint,                      -- ID_TREATMENT: код вида лечения
    treatment_type      text,                        -- TREATMENT: вид лечения
    treatment_method_id bigint,                      -- ID_METHOD: код метода лечения
    treatment_method    text,                        -- METHOD: метод лечения

    vmp_group           integer,                     -- GROUP: группа ВМП
    part                integer
                        check (part in (1, 2, 3)),   -- PART: раздел
    finance             text,                        -- FINANCE: норматив финансовых затрат
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- SORT: сортировка из источника
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_high_tech_medical_care_type_profile_id
    on data.high_tech_medical_care_type (profile_id);

create index if not exists idx_high_tech_medical_care_type_icd10_code
    on data.high_tech_medical_care_type (icd10_code);