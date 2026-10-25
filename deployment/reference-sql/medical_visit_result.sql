------------ medical_visit_result ------------ 1.2.643.5.1.13.13.11.1046
create table if not exists data.medical_visit_result (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                text not null,         -- NAME: полное название

    form_025_code       text,                  -- FORM_025: строка формы 025-1/у
    form_066_02_code    integer,               -- FORM_066: строка формы 066/у-02
    form_066_02_name    text,                  -- NAME_SYNONYM: название в форме 066/у-02
    form_066_u_code     integer,               -- FORM_066_u: строка формы 066/у
    form_066_u_name     text,                  -- NAME_066_u: название в форме 066/у

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      text                   -- Локальные поисковые синонимы
);