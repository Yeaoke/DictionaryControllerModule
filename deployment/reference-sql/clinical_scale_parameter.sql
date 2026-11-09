create table if not exists data.clinical_scale_parameter (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                varchar(1000) not null,         -- NAME: название раздела или фактора
    vital_parameter_id  bigint,                -- VITAL_PARAMETER: ID витального параметра
    point               varchar(5000),                  -- POINT: балльная оценка
    interpretation_group_code bigint,         -- ID_INTERPRETATION: группировочный код
    
    grouping_scale      integer,               -- GROUPING_SCALE: группировка по шкалам

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
