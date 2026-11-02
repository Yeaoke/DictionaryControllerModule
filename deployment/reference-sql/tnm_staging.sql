------------ tnm_staging ------------ 1.2.643.5.1.13.13.99.2.546
create table if not exists data.tnm_staging (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    topography_name     varchar(200) not null,         -- ShortNameOfTopography
    icdo_topography     varchar(100),                  -- ICDOTopography: МКБ-О топография
    morphology          varchar(500) not null,         -- Morphology: гистологическая группа
    stage               varchar(100) not null,         -- Stage: стадирование по TNM

    tumor               varchar(100) not null,         -- Tumor: категория T
    tumor_category_id   bigint,                -- ID_Tumor: код категории
    nodus               varchar(100),                  -- Nodus: категория N
    nodus_category_id   bigint,                -- ID_Nodus: код категории
    metastasis          varchar(100) not null,         -- Metastasis: категория M
    metastasis_category_id bigint,             -- ID_Metastasis: код категории
    addition            varchar(2000),                  -- Addition: дополнительная информация
    addition_category_id bigint,               -- ID_Addition: код дополнительной информации

    classification      integer not null
                        check (classification in (1, 2, 3)),
                                               -- Classification: 1 — клиническая,
                                               -- 2 — патологоанатомическая, 3 — обе
    tnm_version         integer not null,      -- Version: версия классификации TNM

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);

create index if not exists idx_tnm_staging_icdo_topography
    on data.tnm_staging (icdo_topography);