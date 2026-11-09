create table if not exists data.foms_medical_organization (
    id                  varchar(5000) primary key,            -- UIDMO: уникальный номер записи
    parent_uidmo        varchar(5000),                        -- PARENT_UIDMO: номер родительской записи
    registry_number     varchar(5000),                        -- IDMO: реестровый номер МО
    parent_registry_number varchar(5000),                     -- PARENT_IDMO: номер МО из F031
    medical_org_code    varchar(5000),                        -- MCOD: реестровый код МО

    name                varchar(500) not null,               -- NAM_MOP: полное наименование
    short_name          varchar(5000),                        -- NAM_MOK: сокращенное наименование
    separate_unit_flag  varchar(5000)
                        check (separate_unit_flag in ('0', '1')),
                                                     -- OSP: 0 — головная МО, 1 — ОСП
    medical_org_type    varchar(5000),                        -- VID_MO: вид МО
    departmental_affiliation varchar(5000),                   -- VEDPRI: ведомственная принадлежность
    ownership_code      varchar(5000),                        -- OKFS: форма собственности

    inn                 varchar(5000),                        -- INN
    kpp                 varchar(5000),                        -- KPP
    ogrn                varchar(5000),                        -- OGRN
    organization_oid    varchar(5000),                        -- OID_MO: OID МО / ОСП
    subdivision_oid     varchar(5000),                        -- OID_SPMO: OID структурного подразделения

    region_name         varchar(5000),                        -- SUBJ: субъект РФ участия в ТПОМС
    region_oktmo_code   varchar(5000),                        -- OKTMO_P: код территории
    gar_address_id      varchar(5000),                        -- GAR_ADDRESS: номер адреса в ГАР
    legal_address       varchar(5000),                        -- JURADDRESS_ADDRESS: юридический адрес
    legal_postal_code   varchar(5000),                        -- JURADDRESS_INDEX: почтовый индекс
    email               varchar(5000),                        -- EMAIL
    phone               varchar(5000),                        -- PHONE
    fax                 varchar(5000),                        -- FAX

    oms_started_at      timestamp without time zone, -- D_BEGIN_OMS: начало участия в ОМС
    registry_included_at timestamp without time zone,-- D_BEGIN: включение в реестр
    registry_excluded_at timestamp without time zone,-- D_END: исключение из реестра
    exclusion_reason    varchar(5000),                        -- NAME_E: причина и основание исключения

    valid_from          timestamp without time zone, -- DATEBEG: начало действия записи
    valid_to            timestamp without time zone, -- DATEEND: окончание действия записи

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(5000)                         -- Локальные поисковые синонимы
);
