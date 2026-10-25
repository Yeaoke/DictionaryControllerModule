------------ medical_care_profile ------------ 1.2.643.5.1.13.13.11.1119
create table if not exists data.medical_care_profile (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- PROFILE: профиль медицинской помощи
    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);