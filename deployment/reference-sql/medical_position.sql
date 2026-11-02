------------ medical_position ------------ 1.2.643.5.1.13.13.11.1002
create table if not exists data.medical_position (
    id                  bigint primary key,          -- ID: идентификатор Минздрава
    parent_id           bigint,                      -- PID: родительская запись
    name                varchar(200) not null,               -- NAME: название должности
    equivalent          varchar(500),                        -- EQUIVALENT: эквивалентное название

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10) not null,         -- SORT: порядок сортировки
    search_synonym      varchar(100),                        -- Локальные поисковые синонимы

    normative_id        bigint,                      -- NORMATIVE: ID НПА
    group_flag          integer,                     -- GROUP: 1 — группировочная запись
    form_30             integer,                     -- FORM_30: код формы № 30
    actual              integer not null
                        check (actual in (0, 1)),     -- ACTUAL: актуальность в источнике
    end_date            timestamp without time zone, -- DATA_END: окончание действия
    comment             varchar(2000),                        -- COMMENT: комментарий

    need_qual           integer,                     -- NEED_QUAL: признак аттестации
    zs                  integer,                     -- ZS: участие в программе
    need_cert           integer                      -- NEED_CERT: сертификат/аккредитация
);

create index if not exists idx_medical_position_parent_id
    on data.medical_position (parent_id);