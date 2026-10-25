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