------------ bed_profile ------------ 1.2.643.5.1.13.13.11.1069
create table if not exists data.bed_profile (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PID: родительская запись
    name                text not null,               -- NAME: полное название
    age_group           integer
                        check (age_group in (0, 1, 2)), -- AgeGROUP: 0 — смешанный,
                                                       -- 1 — взрослые, 2 — дети
    relevance           integer
                        check (relevance in (0, 1)),  -- REL: 1 — актуальна, 0 — упразднена
    abolished_at        timestamp without time zone, -- DATEOUT: дата упразднения
    form_30_code        text,                        -- F30: код строки формы № 30
    section_code        varchar(1)
                        check (section_code in ('1', '2', '3')), -- RAZDEL: раздел

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- SORT: сортировка из источника
    search_synonym      text                         -- Локальные поисковые синонимы
);

create index if not exists idx_bed_profile_parent_id
    on data.bed_profile (parent_id);