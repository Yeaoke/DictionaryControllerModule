create table if not exists data.implantable_assistive_device_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT: родительская запись
    name                varchar(500) not null,         -- NAME: наименование вида изделия
    rzn_code            varchar(5000),                  -- RZN: код типа изделия Росздравнадзора
    disease_code        varchar(5000),                  -- DISEASE: идентификатор из справочника ФРЛОЗ
    actual              boolean,               -- ACTUAL: актуальность в источнике
    existence_npa       boolean,               -- EXISTENCE_NPA: наличие в перечне НПА
    source_order        varchar(5000),                  -- ORDER: порядок сортировки источника

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
