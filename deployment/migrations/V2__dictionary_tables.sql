------------ ambulance_call_order ------------ 1.2.643.5.1.13.13.11.1525
create table if not exists data.ambulance_call_order (
    id                  bigint primary key,    -- Id: идентификатор Минздрава
    name                text not null,         -- Name: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ ambulance_team_type ------------ 1.2.643.5.1.13.13.99.2.1076
create table if not exists data.ambulance_team_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- NAME: наименование
    form_30_code        text,                  -- FORM_30: код строки формы № 30

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_ambulance_team_type_parent_id
    on data.ambulance_team_type (parent_id);

------------ anatomical_location ------------ 1.2.643.5.1.13.13.11.1477
create table if not exists data.anatomical_location (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- ID_PARENT: родительская запись
    name                text not null,         -- NAME: наименование
    english_name        text,                  -- NAME_ENG: английское наименование
    snomed_code         text,                  -- SNOMED_CT: код SNOMED CT
    anatomical_region   text,                  -- ANATOMIC_FIELD: анатомическая область
    laterality          text,                  -- LATERALITY: возможность уточнения стороны
    synonyms            text,                  -- SYNONYMS: синонимы из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_anatomical_location_parent_id
    on data.anatomical_location (parent_id);

------------ anesthesia_type ------------ 1.2.643.5.1.13.13.11.1033
create table if not exists data.anesthesia_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- Parent: родительская запись
    name                text not null,         -- Name: наименование вида анестезии
    anesthesia_group    text,                  -- Group: группировочное название
    synonyms            text,                  -- Synonym: альтернативные названия
    source_order        text,                  -- SORT: сортировка из источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_anesthesia_type_parent_id
    on data.anesthesia_type (parent_id);

------------ bacterium ------------ 1.2.643.5.1.13.13.11.1087
create table if not exists data.bacterium (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- ID_PARENT: родительская запись
    hierarchy_level     integer,               -- LEVEL: уровень иерархии
    name                text not null,         -- FULLNAME: полное наименование
    formatted_name      text,                  -- FORMATNAME: форматированное наименование
    child_count         integer,               -- CHILDCOUNT: число дочерних элементов
    synonyms            text,                  -- SYNONIMS: синонимы из источника
    snomed_code         text,                  -- SNOMED: код SNOMED CT
    ncbi_id             bigint,                -- ID_NCBI: код NCBI
    gram                text,                  -- GRAM: окраска по Граму
    human               boolean,               -- HUMAN: этиологическая значимость
                                               -- для заболеваний человека

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- SORT: сортировка из источника
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_bacterium_parent_id
    on data.bacterium (parent_id);

------------ bed_profile ------------ 1.2.643.5.1.13.13.11.1069
create table if not exists data.bed_profile (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PID: родительская запись
    name                text not null,               -- NAME: полное название
    age_group           integer
                        check (age_group in (0, 1, 2)), -- AgeGROUP: 0 — смешанный,
                                                       -- 1 — взрослые, 2 — дети
    relevance           integer
                        check (relevance in (0, 1)),  -- REL: 1 — актуальна, 0 — упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения
    form_30_code        text,                        -- F30: код строки формы № 30
    section_code        varchar(1)
                        check (section_code in ('1', '2', '3')), -- RAZDEL: раздел

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- SORT: сортировка из источника
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_bed_profile_parent_id
    on data.bed_profile (parent_id);

------------ biopsy_collection_method ------------ 1.2.643.5.1.13.13.99.2.33
create table if not exists data.biopsy_collection_method (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ biopsy_complexity_category ------------ 1.2.643.5.1.13.13.11.1549
create table if not exists data.biopsy_complexity_category (
    id                  bigint primary key,    -- Id: идентификатор Минздрава
    name                text not null,         -- Name: наименование
    description         text,                  -- Description: описание категории

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ clinical_scale_parameter ------------ 1.2.643.5.1.13.13.11.1515
create table if not exists data.clinical_scale_parameter (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- NAME: название раздела или фактора
    vital_parameter_id  bigint,                -- VITAL_PARAMETER: ID витального параметра
    point               text,                  -- POINT: балльная оценка
    interpretation_group_code bigint,         -- ID_INTERPRETATION: группировочный код
    
    grouping_scale      integer,               -- GROUPING_SCALE: группировка по шкалам

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_clinical_scale_parameter_parent_id
    on data.clinical_scale_parameter (parent_id);

create index if not exists idx_clinical_scale_parameter_grouping_scale
    on data.clinical_scale_parameter (grouping_scale);

------------ contraindication_or_refusal ------------ 1.2.643.5.1.13.13.99.2.786
create table if not exists data.contraindication_or_refusal (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- CONTRAINDICATION_OR_REFUSAL: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_contraindication_or_refusal_parent_id
    on data.contraindication_or_refusal (parent_id);

------------ disease_nature ------------ 1.2.643.5.1.13.13.11.1049
create table if not exists data.disease_nature (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: наименование
    form_025_1u_code     integer,               -- F_025-1u: код формы № 025-1/у

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ disability_group ------------ 1.2.643.5.1.13.13.11.1053
create table if not exists data.disability_group (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название
    snomed_code         text,                  -- SCTID: код SNOMED CT

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ disease_outcome ------------ 1.2.643.5.1.13.13.11.1491
create table if not exists data.disease_outcome (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                text not null,         -- NAME: наименование исхода
    oms_outcome_code    text,                  -- IDIZ: код для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ dispensary_observation_end_reason ------------ 1.2.643.5.1.13.13.11.1045
create table if not exists data.dispensary_observation_end_reason (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- NAME: наименование
    normative_id        bigint not null,       -- NPA: код нормативно-правового акта

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- SORT: сортировка из источника
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_dispensary_observation_end_reason_parent_id
    on data.dispensary_observation_end_reason (parent_id);

------------ dispensary_observation_status ------------ 1.2.643.5.1.13.13.11.1047
create table if not exists data.dispensary_observation_status (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ drug_administration_route ------------ 1.2.643.5.1.13.13.11.1468
create table if not exists data.drug_administration_route (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT: родительская запись
    name                text not null,         -- NAME_RUS: наименование на русском
    english_name        text not null,         -- NAME_ENG: наименование на английском
    eec_dictionary_code text,                  -- NSI_CODE_EEC: код справочника ЕАЭК
    eec_element_code    text,                  -- NSI_ELEMENT_CODE_EEC: код элемента ЕАЭК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_drug_administration_route_parent_id
    on data.drug_administration_route (parent_id);

------------ foms_bill_type ------------ 1.2.643.5.1.13.13.99.3.42
create table if not exists data.foms_bill_type (
    code                text not null,               -- billcod: код типа счета
    region_okato_code   text not null,               -- tf_okato: код субъекта РФ по ОКАТО
    name                text not null,               -- bill_namp: полное наименование
    short_name          text,                        -- bill_namk: краткое наименование
    payer_org_type      text,                        -- orgType: тип организации-плательщика
    funding_source      text
                        check (funding_source in ('0', '1')),
                                                     -- IS_PAY: 1 — ОМС, 0 — бюджет субъекта
    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (code, region_okato_code)
);

------------ foms_classification_criterion ------------ 1.2.643.5.1.13.13.99.3.6
create table if not exists data.foms_classification_criterion (
    code                text not null,               -- IDDKK: код критерия
    valid_from          timestamp without time zone not null,

    name                text not null,               -- DKKNAME: наименование критерия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (code, valid_from)
);

------------ foms_clinical_statistical_group ------------ 1.2.643.5.1.13.13.99.3.5
create table if not exists data.foms_clinical_statistical_group (
    code                text not null,               -- K_KSG: номер КСГ
    care_condition_code text not null,               -- IDUMP: код условий оказания МП (V006)
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- N_KSG: наименование КСГ
    cost_coefficient    text,                        -- KOEF_Z: коэффициент затратоемкости
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (code, care_condition_code, valid_from)
);

------------ foms_consilium_purpose ------------ 1.2.643.5.1.13.13.99.3.55
create table if not exists data.foms_consilium_purpose (
    id                  text not null,               -- ID_CONS: идентификатор цели
    valid_from          timestamp without time zone not null,

    name                text not null,               -- CONS_NAME: наименование цели
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

------------ foms_control_type ------------ 1.2.643.5.1.13.13.99.3.32
create table if not exists data.foms_control_type (
    id                  bigint not null,             -- IDVID: код вида контроля
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- VIDNAME: наименование вида контроля
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

------------ foms_diagnostic_method ------------ 1.2.643.5.1.13.13.99.3.47
create table if not exists data.foms_diagnostic_method (
    id                  bigint primary key,          -- IDMET: код метода
    name                text not null,               -- N_MET: наименование метода
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ foms_dispanserization_type ------------ 1.2.643.5.1.13.13.99.3.3
create table if not exists data.foms_dispanserization_type (
    id                  text not null,               -- IDDT: код типа диспансеризации
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- DTNAME: наименование типа
    allowed_results     text,                        -- DTRULE: допустимые результаты
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

------------ foms_drug_therapy_medication ------------ 1.2.643.5.1.13.13.99.3.56
create table if not exists data.foms_drug_therapy_medication (
    id                  text not null,               -- ID_LEKP: идентификатор препарата
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- MNN: МНН лекарственного препарата
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

------------ foms_histological_result ------------ 1.2.643.5.1.13.13.99.3.52
create table if not exists data.foms_histological_result (
    id                  bigint primary key,          -- ID_R_M: идентификатор записи
    histological_sign_code text,                     -- ID_Mrf: идентификатор признака N007
    name                text not null,               -- R_M_NAME: наименование результата
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ foms_histological_sign ------------ 1.2.643.5.1.13.13.99.3.51
create table if not exists data.foms_histological_sign (
    id                  bigint primary key,          -- ID_Mrf: идентификатор признака
    name                text not null,               -- Mrf_NAME: наименование признака
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ foms_marker_value ------------ 1.2.643.5.1.13.13.99.3.60
create table if not exists data.foms_marker_value (
    id                  bigint not null,             -- ID_R_I: идентификатор записи
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    code                text,                        -- KOD_R_I: обозначение результата
    name                text not null,               -- R_I_NAME: наименование результата
    marker_id           bigint,                      -- ID_Igh: идентификатор маркера N010
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

create index if not exists idx_foms_marker_value_marker_id
    on data.foms_marker_value (marker_id);

------------ foms_marker ------------ 1.2.643.5.1.13.13.99.3.59
create table if not exists data.foms_marker (
    id                  bigint not null,             -- ID_Igh: идентификатор маркера
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    code                text,                        -- KOD_Igh: обозначение маркера
    name                text not null,               -- Igh_NAME: наименование маркера
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

------------ foms_medical_organization ------------ 1.2.643.5.1.13.13.99.3.2
create table if not exists data.foms_medical_organization (
    id                  text primary key,            -- UIDMO: уникальный номер записи
    parent_uidmo        text,                        -- PARENT_UIDMO: номер родительской записи
    registry_number     text,                        -- IDMO: реестровый номер МО
    parent_registry_number text,                     -- PARENT_IDMO: номер МО из F031
    medical_org_code    text,                        -- MCOD: реестровый код МО

    name                text not null,               -- NAM_MOP: полное наименование
    short_name          text,                        -- NAM_MOK: сокращенное наименование
    separate_unit_flag  text
                        check (separate_unit_flag in ('0', '1')),
                                                     -- OSP: 0 — головная МО, 1 — ОСП
    medical_org_type    text,                        -- VID_MO: вид МО
    departmental_affiliation text,                   -- VEDPRI: ведомственная принадлежность
    ownership_code      text,                        -- OKFS: форма собственности

    inn                 text,                        -- INN
    kpp                 text,                        -- KPP
    ogrn                text,                        -- OGRN
    organization_oid    text,                        -- OID_MO: OID МО / ОСП
    subdivision_oid     text,                        -- OID_SPMO: OID структурного подразделения

    region_name         text,                        -- SUBJ: субъект РФ участия в ТПОМС
    region_oktmo_code   text,                        -- OKTMO_P: код территории
    gar_address_id      text,                        -- GAR_ADDRESS: номер адреса в ГАР
    legal_address       text,                        -- JURADDRESS_ADDRESS: юридический адрес
    legal_postal_code   text,                        -- JURADDRESS_INDEX: почтовый индекс
    email               text,                        -- EMAIL
    phone               text,                        -- PHONE
    fax                 text,                        -- FAX

    oms_started_at      timestamp without time zone, -- D_BEGIN_OMS: начало участия в ОМС
    registry_included_at timestamp without time zone,-- D_BEGIN: включение в реестр
    registry_excluded_at timestamp without time zone,-- D_END: исключение из реестра
    exclusion_reason    text,                        -- NAME_E: причина и основание исключения

    valid_from          timestamp without time zone, -- DATEBEG: начало действия записи
    valid_to            timestamp without time zone, -- DATEEND: окончание действия записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_foms_medical_organization_parent_uidmo
    on data.foms_medical_organization (parent_uidmo);

create index if not exists idx_foms_medical_organization_registry_number
    on data.foms_medical_organization (registry_number);

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

------------ foms_payment_method ------------ 1.2.643.5.1.13.13.99.3.17
create table if not exists data.foms_payment_method (
    id                  bigint not null,             -- IDSP: код способа оплаты
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                varchar(254) not null,       -- SPNAME: наименование способа оплаты
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);

------------ foms_payment_organization_details ------------ 1.2.643.5.1.13.13.99.3.43
create table if not exists data.foms_payment_organization_details (
    bill_type_code      text not null,               -- billcod: код типа счета
    organization_code   bigint not null,             -- orgcod: номер организации
    region_okato_code   text not null,               -- tf_okato: код субъекта РФ
    source_record_id    bigint,                      -- idzap: идентификатор записи

    inn                 text,                        -- inn
    kpp                 text,                        -- kpp
    account_type        text
                        check (account_type in ('1', '2')),
                                                     -- accounttype: 1 — банковский,
                                                     -- 2 — казначейский счет
    account_number      text,                        -- accountnum: номер счета
    correspondent_account text,                      -- corraccount: корреспондентский счет
    bank_name           text,                        -- bankname: наименование банка
    bank_bik            text,                        -- bankbik: БИК банка

    tofk_code           text,                        -- tofk_code: код ТОФК
    tofk_name           text,                        -- tofk_name: наименование ТОФК
    tofk_bik            text,                        -- tofk_bik: БИК ТОФК
    treasury_single_account text,                    -- sta_character: ЕКС
    financial_agency_name text,                      -- name_agency: финансовый орган

    personal_account    text,                        -- personal_account: лицевой счет
    personal_account_purpose text,                   -- function_personal_account
    personal_account_tofk_code text,                 -- code_tofk: код ТОФК по лицевому счету

    income_admin_name   text,                        -- name_income_admin
    income_admin_inn    text,                        -- inn_income_admin
    income_admin_kpp    text,                        -- kpp_income_admin
    personal_account_income_admin boolean,           -- Тип BOOLEAN указан в паспорте

    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (bill_type_code, organization_code, region_okato_code)
);

------------ foms_payment_organization ------------ 1.2.643.5.1.13.13.99.3.1
create table if not exists data.foms_payment_organization (
    id                  text primary key,            -- orgcod: номер организации
    name                text not null,               -- nam_orgp: полное наименование
    short_name          text,                        -- nam_orgk: краткое наименование
    organization_type   text
                        check (organization_type in ('0', '1', '2')),
                                                     -- orgtype: 0 — ФОМС,
                                                     -- 1 — ТФОМС, 2 — СМО
    territorial_fund_code text,                      -- tf_kod: код ТФОМС
    smo_code            text,                        -- smocod: код СМО
    region_okato_code   text,                        -- tf_okato: код субъекта РФ по ОКАТО
    valid_from          timestamp without time zone, -- datebeg: начало действия
    valid_to            timestamp without time zone, -- dateend: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ foms_payment_refusal_reason ------------ 1.2.643.5.1.13.13.99.3.11
create table if not exists data.foms_payment_refusal_reason (
    code                bigint not null,             -- Kod: код ошибки
    name                text not null,               -- Naim: наименование причины отказа
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    refusal_basis       text,                        -- Osn: основание отказа
    service_comment     text,                        -- Komment: служебный комментарий
    control_type_code   integer,                     -- IDVID: код вида контроля, резерв
    penalty_coefficient text,                        -- K_SH: коэффициент штрафа
    nonpayment_coefficient text,                     -- K_NO: коэффициент неоплаты
    form_pg_code        text,                        -- KodPG: код по форме № ПГ
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (code, name, valid_from)
);

------------ foms_surgical_treatment_type ------------ 1.2.643.5.1.13.13.99.3.48
create table if not exists data.foms_surgical_treatment_type (
    id                  bigint primary key,          -- ID_THir: идентификатор типа лечения
    name                text not null,               -- THir_NAME: наименование
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ foms_treatment_type ------------ 1.2.643.5.1.13.13.99.3.54
create table if not exists data.foms_treatment_type (
    id                  bigint primary key,          -- ID_TLech: идентификатор типа лечения
    name                text not null,               -- TLech_NAME: наименование типа лечения
    valid_from          timestamp without time zone, -- DATEBEG: начало действия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

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

------------ high_tech_patient_model ------------ 1.2.643.5.1.13.13.99.2.360
create table if not exists data.high_tech_patient_model (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                text not null,               -- MODEL: модель пациента
    sections            text,                        -- RAZDEL: номер/номера разделов ВМП
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ high_tech_treatment_method ------------ 1.2.643.5.1.13.13.99.2.621
create table if not exists data.high_tech_treatment_method (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                text not null,               -- METHOD: метод лечения
    sections            text,                        -- RAZDEL: номер/номера разделов ВМП
    implantation_obligation integer,                 -- OBLIGATION: обязательность имплантации
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ high_tech_treatment_type ------------ 1.2.643.5.1.13.13.99.2.620
create table if not exists data.high_tech_treatment_type (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    name                text not null,               -- TREATMENT: вид лечения
    valid_from          timestamp without time zone, -- DATE_BEGIN: начало действия
    valid_to            timestamp without time zone, -- DATE_END: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

------------ icd10 ------------ 1.2.643.5.1.13.13.11.1005
create table if not exists data.icd10 (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- ID_PARENT: родительская запись
    code                text,                        -- MKB_CODE: код МКБ-10
    name                text not null,               -- MKB_NAME: название
    rec_code            text,                        -- REC_CODE: строковый код сортировки

    additional_code     integer
                        check (additional_code in (1, 2)), -- ADDL_CODE: 1 — †, 2 — *
    actual              integer
                        check (actual in (0, 1)),     -- ACTUAL: актуальность в источнике
    actuality_changed_at timestamp without time zone, -- DATE: дата изменения актуальности

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_icd10_parent_id
    on data.icd10 (parent_id);

create index if not exists idx_icd10_code
    on data.icd10 (code);

------------ immunobiological_disease_group ------------ 1.2.643.5.1.13.13.99.2.1111
create table if not exists data.immunobiological_disease_group (
    id                  bigint primary key,    -- id: идентификатор Минздрава
    name                text not null,         -- NAME: наименование
    synonyms            text,                  -- SYNONYMS: синонимы из источника
    used_in_elmk        boolean,               -- EPMB: использование в ЭЛМК
    elmk_name           text,                  -- NAME_EPMB: наименование в ЭЛМК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ implantable_assistive_device_type ------------ 1.2.643.5.1.13.13.11.1079
create table if not exists data.implantable_assistive_device_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT: родительская запись
    name                text not null,         -- NAME: наименование вида изделия
    rzn_code            text,                  -- RZN: код типа изделия Росздравнадзора
    disease_code        text,                  -- DISEASE: идентификатор из справочника ФРЛОЗ
    actual              boolean,               -- ACTUAL: актуальность в источнике
    existence_npa       boolean,               -- EXISTENCE_NPA: наличие в перечне НПА
    source_order        text,                  -- ORDER: порядок сортировки источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_implantable_assistive_device_type_parent_id
    on data.implantable_assistive_device_type (parent_id);

------------ injury_type ------------ 1.2.643.5.1.13.13.11.1036
create table if not exists data.injury_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название
    form_066u_02_code   integer,               -- F_066u-02: код формы
    form_066u_02_name   text,                  -- NAME_F_066u-02: название в форме
    form_025u_1_code    text,                  -- F_025u-1: код формы
    form_025u_1_name    text,                  -- NAME_F_025u-1: название в форме

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ laboratory_specimen ------------ 1.2.643.5.1.13.13.11.1081
create table if not exists data.laboratory_specimen (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    specimen_group      text,                  -- GROUP: группа
    material_id         bigint,                -- ID_MATTER: код материала
    material_name       text,                  -- MATTER: материал
    name                text,                  -- SPECIMEN: образец

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Sort: сортировка из источника
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_laboratory_specimen_material_id
    on data.laboratory_specimen (material_id);

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

------------ laterality ------------ 1.2.643.5.1.13.13.99.2.778
create table if not exists data.laterality (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- laterality: наименование стороны

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

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

------------ medical_care_condition ------------ 1.2.643.5.1.13.13.99.2.322
create table if not exists data.medical_care_condition (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                text not null,         -- NAME: наименование
    oms_condition_code  integer,               -- IDUMP: код условия для ОМС (V006)
    comments            text,                  -- COMMENTS: комментарии

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

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

------------ medical_care_location ------------ 1.2.643.5.1.13.13.11.1008
create table if not exists data.medical_care_location (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название
    form_025_1y_flag     integer,               -- F025-1y: 1 — используется в талоне
    oms_visit_place_code integer,              -- ID_MOP: код места обращения для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10) not null,  -- SORT: обязательный код сортировки
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ medical_care_profile ------------ 1.2.643.5.1.13.13.11.1119
create table if not exists data.medical_care_profile (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- PROFILE: профиль медицинской помощи
    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ medical_care_type ------------ 1.2.643.5.1.13.13.11.1034
create table if not exists data.medical_care_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT: родительская запись
    name                text not null,         -- NAME: полное название
    oms_care_type_code  integer,               -- IDVMP: код вида медицинской помощи для ОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10) not null,  -- SORT: обязательный код сортировки
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_medical_care_type_parent_id
    on data.medical_care_type (parent_id);

------------ medical_equipment_type ------------ 1.2.643.5.1.13.13.99.2.253
create table if not exists data.medical_equipment_type (
    id                  bigint primary key,          -- id: идентификатор Минздрава
    parent_id           bigint,                      -- parent_id: родительская запись
    name                text not null,               -- equipment_type: наименование
    available           integer
                        check (available in (0, 1)), -- available: доступность для выбора
    abolished_at        timestamp without time zone, -- date_end: дата упразднения

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_medical_equipment_type_parent_id
    on data.medical_equipment_type (parent_id);

------------ medical_position ------------ 1.2.643.5.1.13.13.11.1002
create table if not exists data.medical_position (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PID: родительская запись
    name                text not null,               -- NAME: название должности
    equivalent          text,                        -- EQUIVALENT: эквивалентное название

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10) not null,         -- SORT: порядок сортировки
    search_synonym      text,                        -- Локальные поисковые синонимы

    normative_id        bigint,                      -- NORMATIVE: ID НПА
    group_flag          integer,                     -- GROUP: 1 — группировочная запись
    form_30             integer,                     -- FORM_30: код формы № 30
    actual              integer not null
                        check (actual in (0, 1)),     -- ACTUAL: актуальность в источнике
    end_date            timestamp without time zone, -- DATA_END: окончание действия
    comment             text,                        -- COMMENT: комментарий

    need_qual           integer,                     -- NEED_QUAL: признак аттестации
    zs                  integer,                     -- ZS: участие в программе
    need_cert           integer                      -- NEED_CERT: сертификат/аккредитация
);

create index if not exists idx_medical_position_parent_id
    on data.medical_position (parent_id);

------------ medical_service ------------ 1.2.643.5.1.13.13.11.1070
create table if not exists data.medical_service (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    code                text not null,               -- S_CODE: код услуги
    name                text not null,               -- NAME: полное название
    relevance           integer
                        check (relevance in (0, 1)),  -- REL: 1 — актуальна, 0 — упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_medical_service_code
    on data.medical_service (code);

------------ medical_specialty ------------ 1.2.643.5.1.13.13.11.1066
create table if not exists data.medical_specialty (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PARENT: родительская запись
    name                text not null,               -- NAME: полное название
    relevance           integer,                     -- REL: 0 — специальность упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения
    ffoms_code          integer,                     -- IDSPEC: код ФФОМС

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_medical_specialty_parent_id
    on data.medical_specialty (parent_id);

------------ medical_visit_reason ------------ 1.2.643.5.1.13.13.99.2.443
create table if not exists data.medical_visit_reason (
    id                  bigint primary key,    -- CODE: идентификатор Минздрава
    name                text not null,         -- NAME: название записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ medical_visit_result ------------ 1.2.643.5.1.13.13.11.1046
create table if not exists data.medical_visit_result (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название

    form_025_code       text,                  -- FORM_025: строка формы 025-1/у
    form_066_02_code    integer,               -- FORM_066: строка формы 066/у-02
    form_066_02_name    text,                  -- NAME_SYNONYM: название в форме 066/у-02
    form_066_u_code     integer,               -- FORM_066_u: строка формы 066/у
    form_066_u_name     text,                  -- NAME_066_u: название в форме 066/у

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ outpatient_visit_purpose ------------ 1.2.643.5.1.13.2.1.1.581
create table if not exists data.outpatient_visit_purpose (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- S_NAME: наименование
    invisible           integer,               -- INVISIBLE: признак невидимости

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ patient_sex ------------ 1.2.643.5.1.13.13.11.1040
create table if not exists data.patient_sex (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

------------ tnm_staging ------------ 1.2.643.5.1.13.13.99.2.546
create table if not exists data.tnm_staging (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    topography_name     text not null,         -- ShortNameOfTopography
    icdo_topography     text,                  -- ICDOTopography: МКБ-О топография
    morphology          text not null,         -- Morphology: гистологическая группа
    stage               text not null,         -- Stage: стадирование по TNM

    tumor               text not null,         -- Tumor: категория T
    tumor_category_id   bigint,                -- ID_Tumor: код категории
    nodus               text,                  -- Nodus: категория N
    nodus_category_id   bigint,                -- ID_Nodus: код категории
    metastasis          text not null,         -- Metastasis: категория M
    metastasis_category_id bigint,             -- ID_Metastasis: код категории
    addition            text,                  -- Addition: дополнительная информация
    addition_category_id bigint,               -- ID_Addition: код дополнительной информации

    classification      integer not null
                        check (classification in (1, 2, 3)),
                                               -- Classification: 1 — клиническая,
                                               -- 2 — патологоанатомическая, 3 — обе
    tnm_version         integer not null,      -- Version: версия классификации TNM

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_tnm_staging_icdo_topography
    on data.tnm_staging (icdo_topography);

------------ unlawful_harm_sign ------------ 1.2.643.5.1.13.13.99.2.933
create table if not exists data.unlawful_harm_sign (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: наименование признака

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);
