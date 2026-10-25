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