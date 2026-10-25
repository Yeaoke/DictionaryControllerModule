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