------------ foms_classification_criterion ------------ 1.2.643.5.1.13.13.99.3.6
create table if not exists data.foms_classification_criterion (
    code                varchar(100) not null,               -- IDDKK: код критерия
    valid_from          timestamp without time zone not null,

    name                varchar(200) not null,               -- DKKNAME: наименование критерия
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      varchar(100),                        -- Локальные поисковые синонимы

    primary key (code, valid_from)
);