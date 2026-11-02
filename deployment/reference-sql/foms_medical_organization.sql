------------ foms_medical_organization ------------ 1.2.643.5.1.13.13.99.3.2
create table if not exists data.foms_medical_organization (
    id                  varchar(100) primary key,            -- UIDMO: уникальный номер записи
    parent_uidmo        varchar(100),                        -- PARENT_UIDMO: номер родительской записи
    registry_number     varchar(100),                        -- IDMO: реестровый номер МО
    parent_registry_number varchar(100),                     -- PARENT_IDMO: номер МО из F031
    medical_org_code    varchar(100),                        -- MCOD: реестровый код МО

    name                varchar(200) not null,               -- NAM_MOP: полное наименование
    short_name          varchar(200),                        -- NAM_MOK: сокращенное наименование
    separate_unit_flag  varchar(1)
                        check (separate_unit_flag in ('0', '1')),
                                                     -- OSP: 0 — головная МО, 1 — ОСП
    medical_org_type    varchar(100),                        -- VID_MO: вид МО
    departmental_affiliation varchar(100),                   -- VEDPRI: ведомственная принадлежность
    ownership_code      varchar(100),                        -- OKFS: форма собственности

    inn                 varchar(32),                        -- INN
    kpp                 varchar(32),                        -- KPP
    ogrn                varchar(32),                        -- OGRN
    organization_oid    varchar(100),                        -- OID_MO: OID МО / ОСП
    subdivision_oid     varchar(100),                        -- OID_SPMO: OID структурного подразделения

    region_name         varchar(200),                        -- SUBJ: субъект РФ участия в ТПОМС
    region_oktmo_code   varchar(100),                        -- OKTMO_P: код территории
    gar_address_id      varchar(100),                        -- GAR_ADDRESS: номер адреса в ГАР
    legal_address       varchar(1000),                        -- JURADDRESS_ADDRESS: юридический адрес
    legal_postal_code   varchar(32),                        -- JURADDRESS_INDEX: почтовый индекс
    email               varchar(320),                        -- EMAIL
    phone               varchar(100),                        -- PHONE
    fax                 varchar(100),                        -- FAX

    oms_started_at      timestamp without time zone, -- D_BEGIN_OMS: начало участия в ОМС
    registry_included_at timestamp without time zone,-- D_BEGIN: включение в реестр
    registry_excluded_at timestamp without time zone,-- D_END: исключение из реестра
    exclusion_reason    varchar(2000),                        -- NAME_E: причина и основание исключения

    valid_from          timestamp without time zone, -- DATEBEG: начало действия записи
    valid_to            timestamp without time zone, -- DATEEND: окончание действия записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(100)                         -- Локальные поисковые синонимы
);

create index if not exists idx_foms_medical_organization_parent_uidmo
    on data.foms_medical_organization (parent_uidmo);

create index if not exists idx_foms_medical_organization_registry_number
    on data.foms_medical_organization (registry_number);