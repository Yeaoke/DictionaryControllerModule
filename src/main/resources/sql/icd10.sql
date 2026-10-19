------------ icd10 ------------ 1.2.643.5.1.13.13.11.1005
create table if not exists data.icd10 (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- ID_PARENT: родительская запись
    code                text,                        -- MKB_CODE: код МКБ-10
    name                text not null,               -- MKB_NAME: название
    rec_code            text,                        -- REC_CODE: строковый код сортировки

    additional_code     integer
                        check (additional_code in (1, 2)), -- ADDL_CODE: 1 — †, 2 — *
    actual              integer
                        check (actual in (0, 1)),     -- ACTUAL: актуальность в источнике
    actuality_changed_at timestamp without time zone, -- DATE: дата изменения актуальности

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_icd10_parent_id
    on data.icd10 (parent_id);

create index if not exists idx_icd10_code
    on data.icd10 (code);