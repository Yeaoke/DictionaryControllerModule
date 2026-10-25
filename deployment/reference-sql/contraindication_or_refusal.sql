------------ contraindication_or_refusal ------------ 1.2.643.5.1.13.13.99.2.786
create table if not exists data.contraindication_or_refusal (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    parent_id           bigint,                -- PARENT_ID: родительская запись
    name                text not null,         -- CONTRAINDICATION_OR_REFUSAL: наименование

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);

create index if not exists idx_contraindication_or_refusal_parent_id
    on data.contraindication_or_refusal (parent_id);