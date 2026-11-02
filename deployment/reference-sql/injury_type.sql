------------ injury_type ------------ 1.2.643.5.1.13.13.11.1036
create table if not exists data.injury_type (
    id                  bigint primary key,    -- ID: идентификатор Минздрава
    name                varchar(200) not null,         -- NAME: полное название
    form_066u_02_code   integer,               -- F_066u-02: код формы
    form_066u_02_name   varchar(200),                  -- NAME_F_066u-02: название в форме
    form_025u_1_code    varchar(100),                  -- F_025u-1: код формы
    form_025u_1_name    varchar(200),                  -- NAME_F_025u-1: название в форме

    is_deleted          char(1) default 'N' not null
                        check (is_deleted in ('Y', 'N')),
    display_order       numeric(10),           -- Локальный порядок отображения
    search_synonym      varchar(100)                   -- Локальные поисковые синонимы
);