------------ foms_drug_therapy_medication ------------ 1.2.643.5.1.13.13.99.3.56
create table if not exists data.foms_drug_therapy_medication (
    id                  text not null,               -- ID_LEKP: идентификатор препарата
    valid_from          timestamp without time zone not null,
                                                     -- DATEBEG: начало действия
    name                text not null,               -- MNN: МНН лекарственного препарата
    valid_to            timestamp without time zone, -- DATEEND: окончание действия

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),                 -- Локальный порядок отображения
    search_synonym      text,                        -- Локальные поисковые синонимы

    primary key (id, valid_from)
);