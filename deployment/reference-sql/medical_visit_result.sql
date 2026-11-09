create table if not exists data.medical_visit_result (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(500) not null,         -- NAME: полное название

    form_025_code       varchar(5000),                  -- FORM_025: строка формы 025-1/у
    form_066_02_code    integer,               -- FORM_066: строка формы 066/у-02
    form_066_02_name    varchar(5000),                  -- NAME_SYNONYM: название в форме 066/у-02
    form_066_u_code     integer,               -- FORM_066_u: строка формы 066/у
    form_066_u_name     varchar(5000),                  -- NAME_066_u: название в форме 066/у

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(5000)                   -- Локальные поисковые синонимы
);
