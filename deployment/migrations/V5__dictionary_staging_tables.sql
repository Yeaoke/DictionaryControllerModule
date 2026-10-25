-- Typed staging tables. Source keys are nullable and non-unique so rejected rows can be retained.
-- raw_row_id identifies an input row; it is never a generated dictionary ID.

CREATE TABLE data.dsa_raw_ambulance_call_order (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_ambulance_team_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    form_30_code text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_anatomical_location (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    english_name text,
    snomed_code text,
    anatomical_region text,
    laterality text,
    synonyms text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_anesthesia_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    anesthesia_group text,
    synonyms text,
    source_order text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_bacterium (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    hierarchy_level integer,
    name text,
    formatted_name text,
    child_count integer,
    synonyms text,
    snomed_code text,
    ncbi_id bigint,
    gram text,
    human boolean,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_bed_profile (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    age_group integer,
    relevance integer,
    abolished_at timestamp without time zone,
    form_30_code text,
    section_code varchar(1),
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_biopsy_collection_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_biopsy_complexity_category (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    description text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_clinical_scale_parameter (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    vital_parameter_id bigint,
    point text,
    interpretation_group_code bigint,
    grouping_scale integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_contraindication_or_refusal (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_disease_nature (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    form_025_1u_code integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_disability_group (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    snomed_code text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_disease_outcome (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    oms_outcome_code text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_dispensary_observation_end_reason (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    normative_id bigint,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_dispensary_observation_status (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_drug_administration_route (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    english_name text,
    eec_dictionary_code text,
    eec_element_code text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_foms_bill_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text,
    region_okato_code text,
    name text,
    short_name text,
    payer_org_type text,
    funding_source text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_classification_criterion (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text,
    valid_from timestamp without time zone,
    name text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_clinical_statistical_group (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text,
    care_condition_code text,
    valid_from timestamp without time zone,
    name text,
    cost_coefficient text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_consilium_purpose (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    valid_from timestamp without time zone,
    name text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_control_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    valid_from timestamp without time zone,
    name text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_diagnostic_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_foms_dispanserization_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    valid_from timestamp without time zone,
    name text,
    allowed_results text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_drug_therapy_medication (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    valid_from timestamp without time zone,
    name text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_histological_result (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    histological_sign_code text,
    name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_foms_histological_sign (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_foms_marker_value (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    valid_from timestamp without time zone,
    code text,
    name text,
    marker_id bigint,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_marker (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    valid_from timestamp without time zone,
    code text,
    name text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_medical_organization (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    parent_uidmo text,
    registry_number text,
    parent_registry_number text,
    medical_org_code text,
    name text,
    short_name text,
    separate_unit_flag text,
    medical_org_type text,
    departmental_affiliation text,
    ownership_code text,
    inn text,
    kpp text,
    ogrn text,
    organization_oid text,
    subdivision_oid text,
    region_name text,
    region_oktmo_code text,
    gar_address_id text,
    legal_address text,
    legal_postal_code text,
    email text,
    phone text,
    fax text,
    oms_started_at timestamp without time zone,
    registry_included_at timestamp without time zone,
    registry_excluded_at timestamp without time zone,
    exclusion_reason text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id text
);

CREATE TABLE data.dsa_raw_foms_medical_quality_expert (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    registry_number text,
    legacy_expert_code text,
    region_oktmo_code text,
    region_name text,
    work_phone text,
    mobile_phone text,
    email text,
    registry_created_at timestamp without time zone,
    registry_excluded_at timestamp without time zone,
    exclusion_reason text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id text
);

CREATE TABLE data.dsa_raw_foms_payment_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    valid_from timestamp without time zone,
    name varchar(254),
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_payment_organization_details (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_type_code text,
    organization_code bigint,
    region_okato_code text,
    source_record_id bigint,
    inn text,
    kpp text,
    account_type text,
    account_number text,
    correspondent_account text,
    bank_name text,
    bank_bik text,
    tofk_code text,
    tofk_name text,
    tofk_bik text,
    treasury_single_account text,
    financial_agency_name text,
    personal_account text,
    personal_account_purpose text,
    personal_account_tofk_code text,
    income_admin_name text,
    income_admin_inn text,
    income_admin_kpp text,
    personal_account_income_admin boolean,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_payment_organization (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    name text,
    short_name text,
    organization_type text,
    territorial_fund_code text,
    smo_code text,
    region_okato_code text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id text
);

CREATE TABLE data.dsa_raw_foms_payment_refusal_reason (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code bigint,
    name text,
    valid_from timestamp without time zone,
    refusal_basis text,
    service_comment text,
    control_type_code integer,
    penalty_coefficient text,
    nonpayment_coefficient text,
    form_pg_code text,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_key jsonb
);

CREATE TABLE data.dsa_raw_foms_surgical_treatment_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_foms_treatment_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_high_tech_medical_care_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    name_id bigint,
    profile_id bigint,
    profile_name text,
    icd10_code text,
    patient_model_id bigint,
    patient_model text,
    treatment_type_id bigint,
    treatment_type text,
    treatment_method_id bigint,
    treatment_method text,
    vmp_group integer,
    part integer,
    finance text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_high_tech_patient_model (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    sections text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_high_tech_treatment_method (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    sections text,
    implantation_obligation integer,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_high_tech_treatment_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_icd10 (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    code text,
    name text,
    rec_code text,
    additional_code integer,
    actual integer,
    actuality_changed_at timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_immunobiological_disease_group (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    synonyms text,
    used_in_elmk boolean,
    elmk_name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_implantable_assistive_device_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    rzn_code text,
    disease_code text,
    actual boolean,
    existence_npa boolean,
    source_order text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_injury_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    form_066u_02_code integer,
    form_066u_02_name text,
    form_025u_1_code text,
    form_025u_1_name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_laboratory_specimen (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    specimen_group text,
    material_id bigint,
    material_name text,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_laboratory_test (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    name text,
    short_name text,
    english_name text,
    synonyms text,
    loinc_code text,
    analyte text,
    analyte_characteristic text,
    measurement text,
    unit text,
    specimen text,
    time_characteristic text,
    method_type text,
    scale_type text,
    test_status text,
    test_group text,
    nmu_codes text,
    source_order text,
    display_order numeric(10),
    reject_reason text,
    new_id text
);

CREATE TABLE data.dsa_raw_laterality (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_measurement_unit (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    short_name text,
    print_name text,
    measurement text,
    ucum_code text,
    coefficient text,
    formula text,
    conversion_unit_id bigint,
    conversion_unit_name text,
    okei_code text,
    eec_dictionary_code text,
    eec_element_code text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_care_condition (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    oms_condition_code integer,
    comments text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_care_form (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    oms_care_form_code integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_care_location (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    form_025_1y_flag integer,
    oms_visit_place_code integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_care_profile (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_care_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    oms_care_type_code integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_equipment_type (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    available integer,
    abolished_at timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_position (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    equivalent text,
    display_order numeric(10),
    normative_id bigint,
    group_flag integer,
    form_30 integer,
    actual integer,
    end_date timestamp without time zone,
    comment text,
    need_qual integer,
    zs integer,
    need_cert integer,
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_service (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    code text,
    name text,
    relevance integer,
    abolished_at timestamp without time zone,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_specialty (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    parent_id bigint,
    name text,
    relevance integer,
    abolished_at timestamp without time zone,
    ffoms_code integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_visit_reason (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_medical_visit_result (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    form_025_code text,
    form_066_02_code integer,
    form_066_02_name text,
    form_066_u_code integer,
    form_066_u_name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_outpatient_visit_purpose (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    invisible integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_patient_sex (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_tnm_staging (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    topography_name text,
    icdo_topography text,
    morphology text,
    stage text,
    tumor text,
    tumor_category_id bigint,
    nodus text,
    nodus_category_id bigint,
    metastasis text,
    metastasis_category_id bigint,
    addition text,
    addition_category_id bigint,
    classification integer,
    tnm_version integer,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);

CREATE TABLE data.dsa_raw_unlawful_harm_sign (
    raw_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint,
    name text,
    display_order numeric(10),
    reject_reason text,
    new_id bigint
);
