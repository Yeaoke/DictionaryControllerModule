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