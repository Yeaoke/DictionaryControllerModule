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