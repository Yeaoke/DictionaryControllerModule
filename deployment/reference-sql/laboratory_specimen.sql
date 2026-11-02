------------ laboratory_specimen ------------ 1.2.643.5.1.13.13.11.1081
create table if not exists data.laboratory_specimen (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    specimen_group      varchar(500),                  -- GROUP: группа
    material_id         bigint,                -- ID_MATTER: код материала
    material_name       varchar(200),                  -- MATTER: материал
    name                varchar(200),                  -- SPECIMEN: образец

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Sort: сортировка из источника
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);

create index if not exists idx_laboratory_specimen_material_id
    on data.laboratory_specimen (material_id);