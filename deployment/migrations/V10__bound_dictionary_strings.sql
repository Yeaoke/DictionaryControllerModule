-- Bound previously unbounded string columns in module-owned tables only.
-- Existing varchar(n), char(n), external logging/user tables and procedures are unchanged.
-- All tables are locked before checking values, preventing concurrent oversized inserts.
-- Raising an exception aborts this entire migration; values are never truncated.
DO $migration$
DECLARE
    owned_tables constant varchar(63)[] := ARRAY[
        'ambulance_call_order',
        'ambulance_team_type',
        'anatomical_location',
        'anesthesia_type',
        'bacterium',
        'bed_profile',
        'biopsy_collection_method',
        'biopsy_complexity_category',
        'clinical_scale_parameter',
        'contraindication_or_refusal',
        'direction_type',
        'disability_group',
        'disease_nature',
        'disease_outcome',
        'dispensary_observation_end_reason',
        'dispensary_observation_status',
        'drug_administration_route',
        'dsa_load_batch',
        'dsa_loaded_version',
        'dsa_raw_ambulance_call_order',
        'dsa_raw_ambulance_team_type',
        'dsa_raw_anatomical_location',
        'dsa_raw_anesthesia_type',
        'dsa_raw_bacterium',
        'dsa_raw_bed_profile',
        'dsa_raw_biopsy_collection_method',
        'dsa_raw_biopsy_complexity_category',
        'dsa_raw_clinical_scale_parameter',
        'dsa_raw_contraindication_or_refusal',
        'dsa_raw_direction_type',
        'dsa_raw_disability_group',
        'dsa_raw_disease_nature',
        'dsa_raw_disease_outcome',
        'dsa_raw_dispensary_observation_end_reason',
        'dsa_raw_dispensary_observation_status',
        'dsa_raw_drug_administration_route',
        'dsa_raw_foms_bill_type',
        'dsa_raw_foms_classification_criterion',
        'dsa_raw_foms_clinical_statistical_group',
        'dsa_raw_foms_consilium_purpose',
        'dsa_raw_foms_control_type',
        'dsa_raw_foms_diagnostic_method',
        'dsa_raw_foms_dispanserization_type',
        'dsa_raw_foms_drug_therapy_medication',
        'dsa_raw_foms_histological_result',
        'dsa_raw_foms_histological_sign',
        'dsa_raw_foms_marker',
        'dsa_raw_foms_marker_value',
        'dsa_raw_foms_medical_organization',
        'dsa_raw_foms_medical_quality_expert',
        'dsa_raw_foms_payment_method',
        'dsa_raw_foms_payment_organization',
        'dsa_raw_foms_payment_organization_details',
        'dsa_raw_foms_payment_refusal_reason',
        'dsa_raw_foms_surgical_treatment_type',
        'dsa_raw_foms_treatment_type',
        'dsa_raw_high_tech_medical_care_type',
        'dsa_raw_high_tech_patient_model',
        'dsa_raw_high_tech_treatment_method',
        'dsa_raw_high_tech_treatment_type',
        'dsa_raw_icd10',
        'dsa_raw_immunobiological_disease_group',
        'dsa_raw_implantable_assistive_device_type',
        'dsa_raw_injury_type',
        'dsa_raw_laboratory_specimen',
        'dsa_raw_laboratory_test',
        'dsa_raw_laterality',
        'dsa_raw_measurement_unit',
        'dsa_raw_medical_care_condition',
        'dsa_raw_medical_care_form',
        'dsa_raw_medical_care_location',
        'dsa_raw_medical_care_profile',
        'dsa_raw_medical_care_type',
        'dsa_raw_medical_equipment_type',
        'dsa_raw_medical_position',
        'dsa_raw_medical_service',
        'dsa_raw_medical_specialty',
        'dsa_raw_medical_visit_reason',
        'dsa_raw_medical_visit_result',
        'dsa_raw_outpatient_visit_purpose',
        'dsa_raw_patient_sex',
        'dsa_raw_tnm_staging',
        'dsa_raw_unlawful_harm_sign',
        'foms_bill_type',
        'foms_classification_criterion',
        'foms_clinical_statistical_group',
        'foms_consilium_purpose',
        'foms_control_type',
        'foms_diagnostic_method',
        'foms_dispanserization_type',
        'foms_drug_therapy_medication',
        'foms_histological_result',
        'foms_histological_sign',
        'foms_marker',
        'foms_marker_value',
        'foms_medical_organization',
        'foms_medical_quality_expert',
        'foms_payment_method',
        'foms_payment_organization',
        'foms_payment_organization_details',
        'foms_payment_refusal_reason',
        'foms_surgical_treatment_type',
        'foms_treatment_type',
        'high_tech_medical_care_type',
        'high_tech_patient_model',
        'high_tech_treatment_method',
        'high_tech_treatment_type',
        'icd10',
        'immunobiological_disease_group',
        'implantable_assistive_device_type',
        'injury_type',
        'laboratory_specimen',
        'laboratory_test',
        'laterality',
        'measurement_unit',
        'medical_care_condition',
        'medical_care_form',
        'medical_care_location',
        'medical_care_profile',
        'medical_care_type',
        'medical_equipment_type',
        'medical_position',
        'medical_service',
        'medical_specialty',
        'medical_visit_reason',
        'medical_visit_result',
        'outpatient_visit_purpose',
        'patient_sex',
        'tnm_staging',
        'unlawful_harm_sign'
    ];
    table_name varchar(63);
    col record;
    longest bigint;
BEGIN
    FOREACH table_name IN ARRAY owned_tables LOOP
        EXECUTE format('LOCK TABLE data.%I IN ACCESS EXCLUSIVE MODE', table_name);
    END LOOP;

    -- Preflight the complete set before altering any column.
    FOR col IN
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        WHERE c.table_schema = 'data'
          AND c.table_name = ANY(owned_tables)
          AND (c.data_type = 'text'
               OR (c.data_type = 'character varying' AND c.character_maximum_length IS NULL))
        ORDER BY c.table_name, c.ordinal_position
    LOOP
        EXECUTE format('SELECT max(char_length(%I)) FROM data.%I',
                       col.column_name, col.table_name) INTO longest;
        IF longest > 10000 THEN
            RAISE EXCEPTION 'Cannot bound data.%.%: maximum length is %, limit is 10000; no values were truncated',
                col.table_name, col.column_name, longest;
        END IF;
    END LOOP;

    FOR col IN
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        WHERE c.table_schema = 'data'
          AND c.table_name = ANY(owned_tables)
          AND (c.data_type = 'text'
               OR (c.data_type = 'character varying' AND c.character_maximum_length IS NULL))
        ORDER BY c.table_name, c.ordinal_position
    LOOP
        EXECUTE format('ALTER TABLE data.%I ALTER COLUMN %I TYPE varchar(10000)',
                       col.table_name, col.column_name);
    END LOOP;
END;
$migration$;