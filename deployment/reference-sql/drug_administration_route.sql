create table if not exists data.drug_administration_route (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT: родительская запись
    name                varchar(500) not null,         -- NAME_RUS: наименование на русском
    english_name        varchar(5000) not null,         -- NAME_ENG: наименование на английском
    eec_dictionary_code varchar(5000),                  -- NSI_CODE_EEC: код справочника ЕАЭК
    eec_element_code    varchar(5000),                  -- NSI_ELEMENT_CODE_EEC: код элемента ЕАЭК

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
