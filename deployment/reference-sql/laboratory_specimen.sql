create table if not exists data.laboratory_specimen (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    specimen_group      varchar(5000),                  -- GROUP: группа
    material_id         bigint,                -- ID_MATTER: код материала
    material_name       varchar(5000),                  -- MATTER: материал
    name                varchar(500),                  -- SPECIMEN: образец

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Sort: сортировка из источника
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
