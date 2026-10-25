-- Complete procedure coverage for the 64-dictionary catalog.
-- direction_type retains its existing V8 procedure (DOC/SORT contract).
-- All other procedures use raw_row_id for per-row results, including duplicate/null keys.
-- Local columns absent from the catalog are preserved on update.
-- External logging/user objects must be supplied by the host system.

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_ambulance_call_order(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'ambulance_call_order';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.ambulance_call_order', 0));
    LOCK TABLE data.dsa_raw_ambulance_call_order IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.ambulance_call_order IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.ambulance_call_order;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_ambulance_call_order;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_ambulance_call_order', 'ambulance_call_order',
        'full', 'dsa_data_load.load_ambulance_call_order', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_ambulance_call_order SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_ambulance_call_order r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.ambulance_call_order t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.ambulance_call_order t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.ambulance_call_order (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_ambulance_call_order SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_ambulance_call_order
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.ambulance_call_order t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_ambulance_call_order r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.ambulance_call_order;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_ambulance_team_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'ambulance_team_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.ambulance_team_type', 0));
    LOCK TABLE data.dsa_raw_ambulance_team_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.ambulance_team_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.ambulance_team_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_ambulance_team_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_ambulance_team_type', 'ambulance_team_type',
        'full', 'dsa_data_load.load_ambulance_team_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_ambulance_team_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_ambulance_team_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.ambulance_team_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.ambulance_team_type t SET parent_id = line.parent_id, name = line.name, form_30_code = line.form_30_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.ambulance_team_type (id, parent_id, name, form_30_code)
                    VALUES (line.id, line.parent_id, line.name, line.form_30_code);
                END IF;
                UPDATE data.dsa_raw_ambulance_team_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_ambulance_team_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.ambulance_team_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_ambulance_team_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.ambulance_team_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_anatomical_location(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'anatomical_location';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.anatomical_location', 0));
    LOCK TABLE data.dsa_raw_anatomical_location IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.anatomical_location IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.anatomical_location;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_anatomical_location;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_anatomical_location', 'anatomical_location',
        'full', 'dsa_data_load.load_anatomical_location', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_anatomical_location SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_anatomical_location r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.anatomical_location t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.anatomical_location t SET parent_id = line.parent_id, name = line.name, english_name = line.english_name, snomed_code = line.snomed_code, anatomical_region = line.anatomical_region, laterality = line.laterality, synonyms = line.synonyms, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.anatomical_location (id, parent_id, name, english_name, snomed_code, anatomical_region, laterality, synonyms)
                    VALUES (line.id, line.parent_id, line.name, line.english_name, line.snomed_code, line.anatomical_region, line.laterality, line.synonyms);
                END IF;
                UPDATE data.dsa_raw_anatomical_location SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_anatomical_location
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.anatomical_location t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_anatomical_location r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.anatomical_location;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_anesthesia_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'anesthesia_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.anesthesia_type', 0));
    LOCK TABLE data.dsa_raw_anesthesia_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.anesthesia_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.anesthesia_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_anesthesia_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_anesthesia_type', 'anesthesia_type',
        'full', 'dsa_data_load.load_anesthesia_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_anesthesia_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_anesthesia_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.anesthesia_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.anesthesia_type t SET parent_id = line.parent_id, name = line.name, anesthesia_group = line.anesthesia_group, synonyms = line.synonyms, source_order = line.source_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.anesthesia_type (id, parent_id, name, anesthesia_group, synonyms, source_order)
                    VALUES (line.id, line.parent_id, line.name, line.anesthesia_group, line.synonyms, line.source_order);
                END IF;
                UPDATE data.dsa_raw_anesthesia_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_anesthesia_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.anesthesia_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_anesthesia_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.anesthesia_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_bacterium(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'bacterium';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.bacterium', 0));
    LOCK TABLE data.dsa_raw_bacterium IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.bacterium IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.bacterium;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_bacterium;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_bacterium', 'bacterium',
        'full', 'dsa_data_load.load_bacterium', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_bacterium SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_bacterium r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.bacterium t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.bacterium t SET parent_id = line.parent_id, hierarchy_level = line.hierarchy_level, name = line.name, formatted_name = line.formatted_name, child_count = line.child_count, synonyms = line.synonyms, snomed_code = line.snomed_code, ncbi_id = line.ncbi_id, gram = line.gram, human = line.human, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.bacterium (id, parent_id, hierarchy_level, name, formatted_name, child_count, synonyms, snomed_code, ncbi_id, gram, human, display_order)
                    VALUES (line.id, line.parent_id, line.hierarchy_level, line.name, line.formatted_name, line.child_count, line.synonyms, line.snomed_code, line.ncbi_id, line.gram, line.human, line.display_order);
                END IF;
                UPDATE data.dsa_raw_bacterium SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_bacterium
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.bacterium t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_bacterium r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.bacterium;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_bed_profile(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'bed_profile';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.bed_profile', 0));
    LOCK TABLE data.dsa_raw_bed_profile IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.bed_profile IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.bed_profile;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_bed_profile;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_bed_profile', 'bed_profile',
        'full', 'dsa_data_load.load_bed_profile', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_bed_profile SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_bed_profile r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.bed_profile t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.bed_profile t SET parent_id = line.parent_id, name = line.name, age_group = line.age_group, relevance = line.relevance, abolished_at = line.abolished_at, form_30_code = line.form_30_code, section_code = line.section_code, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.bed_profile (id, parent_id, name, age_group, relevance, abolished_at, form_30_code, section_code, display_order)
                    VALUES (line.id, line.parent_id, line.name, line.age_group, line.relevance, line.abolished_at, line.form_30_code, line.section_code, line.display_order);
                END IF;
                UPDATE data.dsa_raw_bed_profile SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_bed_profile
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.bed_profile t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_bed_profile r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.bed_profile;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_biopsy_collection_method(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'biopsy_collection_method';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.biopsy_collection_method', 0));
    LOCK TABLE data.dsa_raw_biopsy_collection_method IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.biopsy_collection_method IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.biopsy_collection_method;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_biopsy_collection_method;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_biopsy_collection_method', 'biopsy_collection_method',
        'full', 'dsa_data_load.load_biopsy_collection_method', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_biopsy_collection_method SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_biopsy_collection_method r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.biopsy_collection_method t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.biopsy_collection_method t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.biopsy_collection_method (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_biopsy_collection_method SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_biopsy_collection_method
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.biopsy_collection_method t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_biopsy_collection_method r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.biopsy_collection_method;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_biopsy_complexity_category(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'biopsy_complexity_category';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.biopsy_complexity_category', 0));
    LOCK TABLE data.dsa_raw_biopsy_complexity_category IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.biopsy_complexity_category IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.biopsy_complexity_category;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_biopsy_complexity_category;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_biopsy_complexity_category', 'biopsy_complexity_category',
        'full', 'dsa_data_load.load_biopsy_complexity_category', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_biopsy_complexity_category SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_biopsy_complexity_category r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.biopsy_complexity_category t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.biopsy_complexity_category t SET name = line.name, description = line.description, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.biopsy_complexity_category (id, name, description)
                    VALUES (line.id, line.name, line.description);
                END IF;
                UPDATE data.dsa_raw_biopsy_complexity_category SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_biopsy_complexity_category
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.biopsy_complexity_category t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_biopsy_complexity_category r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.biopsy_complexity_category;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_clinical_scale_parameter(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'clinical_scale_parameter';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.clinical_scale_parameter', 0));
    LOCK TABLE data.dsa_raw_clinical_scale_parameter IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.clinical_scale_parameter IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.clinical_scale_parameter;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_clinical_scale_parameter;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_clinical_scale_parameter', 'clinical_scale_parameter',
        'full', 'dsa_data_load.load_clinical_scale_parameter', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_clinical_scale_parameter SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_clinical_scale_parameter r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.clinical_scale_parameter t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.clinical_scale_parameter t SET parent_id = line.parent_id, name = line.name, vital_parameter_id = line.vital_parameter_id, point = line.point, interpretation_group_code = line.interpretation_group_code, grouping_scale = line.grouping_scale, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.clinical_scale_parameter (id, parent_id, name, vital_parameter_id, point, interpretation_group_code, grouping_scale)
                    VALUES (line.id, line.parent_id, line.name, line.vital_parameter_id, line.point, line.interpretation_group_code, line.grouping_scale);
                END IF;
                UPDATE data.dsa_raw_clinical_scale_parameter SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_clinical_scale_parameter
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.clinical_scale_parameter t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_clinical_scale_parameter r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.clinical_scale_parameter;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_contraindication_or_refusal(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'contraindication_or_refusal';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.contraindication_or_refusal', 0));
    LOCK TABLE data.dsa_raw_contraindication_or_refusal IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.contraindication_or_refusal IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.contraindication_or_refusal;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_contraindication_or_refusal;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_contraindication_or_refusal', 'contraindication_or_refusal',
        'full', 'dsa_data_load.load_contraindication_or_refusal', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_contraindication_or_refusal SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_contraindication_or_refusal r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.contraindication_or_refusal t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.contraindication_or_refusal t SET parent_id = line.parent_id, name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.contraindication_or_refusal (id, parent_id, name)
                    VALUES (line.id, line.parent_id, line.name);
                END IF;
                UPDATE data.dsa_raw_contraindication_or_refusal SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_contraindication_or_refusal
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.contraindication_or_refusal t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_contraindication_or_refusal r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.contraindication_or_refusal;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_disease_nature(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'disease_nature';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.disease_nature', 0));
    LOCK TABLE data.dsa_raw_disease_nature IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.disease_nature IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.disease_nature;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_disease_nature;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_disease_nature', 'disease_nature',
        'full', 'dsa_data_load.load_disease_nature', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_disease_nature SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_disease_nature r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.disease_nature t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.disease_nature t SET name = line.name, form_025_1u_code = line.form_025_1u_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.disease_nature (id, name, form_025_1u_code)
                    VALUES (line.id, line.name, line.form_025_1u_code);
                END IF;
                UPDATE data.dsa_raw_disease_nature SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_disease_nature
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.disease_nature t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_disease_nature r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.disease_nature;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_disability_group(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'disability_group';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.disability_group', 0));
    LOCK TABLE data.dsa_raw_disability_group IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.disability_group IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.disability_group;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_disability_group;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_disability_group', 'disability_group',
        'full', 'dsa_data_load.load_disability_group', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_disability_group SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_disability_group r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.disability_group t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.disability_group t SET name = line.name, snomed_code = line.snomed_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.disability_group (id, name, snomed_code)
                    VALUES (line.id, line.name, line.snomed_code);
                END IF;
                UPDATE data.dsa_raw_disability_group SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_disability_group
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.disability_group t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_disability_group r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.disability_group;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_disease_outcome(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'disease_outcome';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.disease_outcome', 0));
    LOCK TABLE data.dsa_raw_disease_outcome IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.disease_outcome IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.disease_outcome;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_disease_outcome;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_disease_outcome', 'disease_outcome',
        'full', 'dsa_data_load.load_disease_outcome', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_disease_outcome SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_disease_outcome r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.disease_outcome t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.disease_outcome t SET name = line.name, oms_outcome_code = line.oms_outcome_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.disease_outcome (id, name, oms_outcome_code)
                    VALUES (line.id, line.name, line.oms_outcome_code);
                END IF;
                UPDATE data.dsa_raw_disease_outcome SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_disease_outcome
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.disease_outcome t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_disease_outcome r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.disease_outcome;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_dispensary_observation_end_reason(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'dispensary_observation_end_reason';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.dispensary_observation_end_reason', 0));
    LOCK TABLE data.dsa_raw_dispensary_observation_end_reason IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.dispensary_observation_end_reason IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.dispensary_observation_end_reason;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_dispensary_observation_end_reason;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_dispensary_observation_end_reason', 'dispensary_observation_end_reason',
        'full', 'dsa_data_load.load_dispensary_observation_end_reason', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_dispensary_observation_end_reason SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_dispensary_observation_end_reason r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.dispensary_observation_end_reason t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.dispensary_observation_end_reason t SET parent_id = line.parent_id, name = line.name, normative_id = line.normative_id, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.dispensary_observation_end_reason (id, parent_id, name, normative_id, display_order)
                    VALUES (line.id, line.parent_id, line.name, line.normative_id, line.display_order);
                END IF;
                UPDATE data.dsa_raw_dispensary_observation_end_reason SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_dispensary_observation_end_reason
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.dispensary_observation_end_reason t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_dispensary_observation_end_reason r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.dispensary_observation_end_reason;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_dispensary_observation_status(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'dispensary_observation_status';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.dispensary_observation_status', 0));
    LOCK TABLE data.dsa_raw_dispensary_observation_status IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.dispensary_observation_status IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.dispensary_observation_status;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_dispensary_observation_status;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_dispensary_observation_status', 'dispensary_observation_status',
        'full', 'dsa_data_load.load_dispensary_observation_status', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_dispensary_observation_status SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_dispensary_observation_status r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.dispensary_observation_status t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.dispensary_observation_status t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.dispensary_observation_status (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_dispensary_observation_status SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_dispensary_observation_status
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.dispensary_observation_status t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_dispensary_observation_status r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.dispensary_observation_status;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_drug_administration_route(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'drug_administration_route';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.drug_administration_route', 0));
    LOCK TABLE data.dsa_raw_drug_administration_route IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.drug_administration_route IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.drug_administration_route;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_drug_administration_route;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_drug_administration_route', 'drug_administration_route',
        'full', 'dsa_data_load.load_drug_administration_route', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_drug_administration_route SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_drug_administration_route r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.drug_administration_route t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.drug_administration_route t SET parent_id = line.parent_id, name = line.name, english_name = line.english_name, eec_dictionary_code = line.eec_dictionary_code, eec_element_code = line.eec_element_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.drug_administration_route (id, parent_id, name, english_name, eec_dictionary_code, eec_element_code)
                    VALUES (line.id, line.parent_id, line.name, line.english_name, line.eec_dictionary_code, line.eec_element_code);
                END IF;
                UPDATE data.dsa_raw_drug_administration_route SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_drug_administration_route
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.drug_administration_route t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_drug_administration_route r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.drug_administration_route;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_bill_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_bill_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_bill_type', 0));
    LOCK TABLE data.dsa_raw_foms_bill_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_bill_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_bill_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_bill_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_bill_type', 'foms_bill_type',
        'full', 'dsa_data_load.load_foms_bill_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_bill_type SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.code, r.region_okato_code) AS source_key_count
            FROM data.dsa_raw_foms_bill_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.code IS NULL OR line.region_okato_code IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_bill_type t WHERE t.code = line.code AND t.region_okato_code = line.region_okato_code) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_bill_type t SET name = line.name, short_name = line.short_name, payer_org_type = line.payer_org_type, funding_source = line.funding_source, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.code = line.code AND t.region_okato_code = line.region_okato_code;
                ELSE
                    INSERT INTO data.foms_bill_type (code, region_okato_code, name, short_name, payer_org_type, funding_source, valid_from, valid_to)
                    VALUES (line.code, line.region_okato_code, line.name, line.short_name, line.payer_org_type, line.funding_source, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_bill_type SET new_key = jsonb_build_object('code', line.code, 'region_okato_code', line.region_okato_code)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_bill_type
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_bill_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_bill_type r WHERE r.code = t.code AND r.region_okato_code = t.region_okato_code);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_bill_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_classification_criterion(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_classification_criterion';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_classification_criterion', 0));
    LOCK TABLE data.dsa_raw_foms_classification_criterion IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_classification_criterion IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_classification_criterion;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_classification_criterion;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_classification_criterion', 'foms_classification_criterion',
        'full', 'dsa_data_load.load_foms_classification_criterion', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_classification_criterion SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.code, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_classification_criterion r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.code IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_classification_criterion t WHERE t.code = line.code AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_classification_criterion t SET name = line.name, valid_to = line.valid_to, is_deleted = 'N' WHERE t.code = line.code AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_classification_criterion (code, valid_from, name, valid_to)
                    VALUES (line.code, line.valid_from, line.name, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_classification_criterion SET new_key = jsonb_build_object('code', line.code, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_classification_criterion
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_classification_criterion t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_classification_criterion r WHERE r.code = t.code AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_classification_criterion;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_clinical_statistical_group(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_clinical_statistical_group';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_clinical_statistical_group', 0));
    LOCK TABLE data.dsa_raw_foms_clinical_statistical_group IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_clinical_statistical_group IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_clinical_statistical_group;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_clinical_statistical_group;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_clinical_statistical_group', 'foms_clinical_statistical_group',
        'full', 'dsa_data_load.load_foms_clinical_statistical_group', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_clinical_statistical_group SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.code, r.care_condition_code, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_clinical_statistical_group r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.code IS NULL OR line.care_condition_code IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_clinical_statistical_group t WHERE t.code = line.code AND t.care_condition_code = line.care_condition_code AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_clinical_statistical_group t SET name = line.name, cost_coefficient = line.cost_coefficient, valid_to = line.valid_to, is_deleted = 'N' WHERE t.code = line.code AND t.care_condition_code = line.care_condition_code AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_clinical_statistical_group (code, care_condition_code, valid_from, name, cost_coefficient, valid_to)
                    VALUES (line.code, line.care_condition_code, line.valid_from, line.name, line.cost_coefficient, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_clinical_statistical_group SET new_key = jsonb_build_object('code', line.code, 'care_condition_code', line.care_condition_code, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_clinical_statistical_group
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_clinical_statistical_group t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_clinical_statistical_group r WHERE r.code = t.code AND r.care_condition_code = t.care_condition_code AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_clinical_statistical_group;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_consilium_purpose(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_consilium_purpose';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_consilium_purpose', 0));
    LOCK TABLE data.dsa_raw_foms_consilium_purpose IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_consilium_purpose IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_consilium_purpose;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_consilium_purpose;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_consilium_purpose', 'foms_consilium_purpose',
        'full', 'dsa_data_load.load_foms_consilium_purpose', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_consilium_purpose SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_consilium_purpose r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_consilium_purpose t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_consilium_purpose t SET name = line.name, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_consilium_purpose (id, valid_from, name, valid_to)
                    VALUES (line.id, line.valid_from, line.name, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_consilium_purpose SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_consilium_purpose
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_consilium_purpose t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_consilium_purpose r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_consilium_purpose;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_control_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_control_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_control_type', 0));
    LOCK TABLE data.dsa_raw_foms_control_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_control_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_control_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_control_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_control_type', 'foms_control_type',
        'full', 'dsa_data_load.load_foms_control_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_control_type SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_control_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_control_type t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_control_type t SET name = line.name, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_control_type (id, valid_from, name, valid_to)
                    VALUES (line.id, line.valid_from, line.name, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_control_type SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_control_type
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_control_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_control_type r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_control_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_diagnostic_method(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_diagnostic_method';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_diagnostic_method', 0));
    LOCK TABLE data.dsa_raw_foms_diagnostic_method IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_diagnostic_method IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_diagnostic_method;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_diagnostic_method;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_diagnostic_method', 'foms_diagnostic_method',
        'full', 'dsa_data_load.load_foms_diagnostic_method', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_diagnostic_method SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_diagnostic_method r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_diagnostic_method t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_diagnostic_method t SET name = line.name, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_diagnostic_method (id, name, valid_from, valid_to)
                    VALUES (line.id, line.name, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_diagnostic_method SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_diagnostic_method
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_diagnostic_method t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_diagnostic_method r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_diagnostic_method;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_dispanserization_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_dispanserization_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_dispanserization_type', 0));
    LOCK TABLE data.dsa_raw_foms_dispanserization_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_dispanserization_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_dispanserization_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_dispanserization_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_dispanserization_type', 'foms_dispanserization_type',
        'full', 'dsa_data_load.load_foms_dispanserization_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_dispanserization_type SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_dispanserization_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_dispanserization_type t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_dispanserization_type t SET name = line.name, allowed_results = line.allowed_results, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_dispanserization_type (id, valid_from, name, allowed_results, valid_to)
                    VALUES (line.id, line.valid_from, line.name, line.allowed_results, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_dispanserization_type SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_dispanserization_type
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_dispanserization_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_dispanserization_type r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_dispanserization_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_drug_therapy_medication(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_drug_therapy_medication';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_drug_therapy_medication', 0));
    LOCK TABLE data.dsa_raw_foms_drug_therapy_medication IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_drug_therapy_medication IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_drug_therapy_medication;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_drug_therapy_medication;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_drug_therapy_medication', 'foms_drug_therapy_medication',
        'full', 'dsa_data_load.load_foms_drug_therapy_medication', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_drug_therapy_medication SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_drug_therapy_medication r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_drug_therapy_medication t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_drug_therapy_medication t SET name = line.name, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_drug_therapy_medication (id, valid_from, name, valid_to)
                    VALUES (line.id, line.valid_from, line.name, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_drug_therapy_medication SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_drug_therapy_medication
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_drug_therapy_medication t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_drug_therapy_medication r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_drug_therapy_medication;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_histological_result(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_histological_result';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_histological_result', 0));
    LOCK TABLE data.dsa_raw_foms_histological_result IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_histological_result IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_histological_result;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_histological_result;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_histological_result', 'foms_histological_result',
        'full', 'dsa_data_load.load_foms_histological_result', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_histological_result SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_histological_result r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_histological_result t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_histological_result t SET histological_sign_code = line.histological_sign_code, name = line.name, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_histological_result (id, histological_sign_code, name, valid_from, valid_to)
                    VALUES (line.id, line.histological_sign_code, line.name, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_histological_result SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_histological_result
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_histological_result t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_histological_result r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_histological_result;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_histological_sign(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_histological_sign';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_histological_sign', 0));
    LOCK TABLE data.dsa_raw_foms_histological_sign IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_histological_sign IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_histological_sign;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_histological_sign;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_histological_sign', 'foms_histological_sign',
        'full', 'dsa_data_load.load_foms_histological_sign', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_histological_sign SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_histological_sign r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_histological_sign t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_histological_sign t SET name = line.name, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_histological_sign (id, name, valid_from, valid_to)
                    VALUES (line.id, line.name, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_histological_sign SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_histological_sign
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_histological_sign t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_histological_sign r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_histological_sign;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_marker_value(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_marker_value';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_marker_value', 0));
    LOCK TABLE data.dsa_raw_foms_marker_value IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_marker_value IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_marker_value;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_marker_value;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_marker_value', 'foms_marker_value',
        'full', 'dsa_data_load.load_foms_marker_value', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_marker_value SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_marker_value r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_marker_value t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_marker_value t SET code = line.code, name = line.name, marker_id = line.marker_id, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_marker_value (id, valid_from, code, name, marker_id, valid_to)
                    VALUES (line.id, line.valid_from, line.code, line.name, line.marker_id, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_marker_value SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_marker_value
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_marker_value t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_marker_value r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_marker_value;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_marker(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_marker';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_marker', 0));
    LOCK TABLE data.dsa_raw_foms_marker IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_marker IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_marker;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_marker;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_marker', 'foms_marker',
        'full', 'dsa_data_load.load_foms_marker', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_marker SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_marker r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_marker t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_marker t SET code = line.code, name = line.name, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_marker (id, valid_from, code, name, valid_to)
                    VALUES (line.id, line.valid_from, line.code, line.name, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_marker SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_marker
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_marker t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_marker r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_marker;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_medical_organization(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_medical_organization';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_medical_organization', 0));
    LOCK TABLE data.dsa_raw_foms_medical_organization IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_medical_organization IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_medical_organization;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_medical_organization;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_medical_organization', 'foms_medical_organization',
        'full', 'dsa_data_load.load_foms_medical_organization', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_medical_organization SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_medical_organization r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_medical_organization t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_medical_organization t SET parent_uidmo = line.parent_uidmo, registry_number = line.registry_number, parent_registry_number = line.parent_registry_number, medical_org_code = line.medical_org_code, name = line.name, short_name = line.short_name, separate_unit_flag = line.separate_unit_flag, medical_org_type = line.medical_org_type, departmental_affiliation = line.departmental_affiliation, ownership_code = line.ownership_code, inn = line.inn, kpp = line.kpp, ogrn = line.ogrn, organization_oid = line.organization_oid, subdivision_oid = line.subdivision_oid, region_name = line.region_name, region_oktmo_code = line.region_oktmo_code, gar_address_id = line.gar_address_id, legal_address = line.legal_address, legal_postal_code = line.legal_postal_code, email = line.email, phone = line.phone, fax = line.fax, oms_started_at = line.oms_started_at, registry_included_at = line.registry_included_at, registry_excluded_at = line.registry_excluded_at, exclusion_reason = line.exclusion_reason, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_medical_organization (id, parent_uidmo, registry_number, parent_registry_number, medical_org_code, name, short_name, separate_unit_flag, medical_org_type, departmental_affiliation, ownership_code, inn, kpp, ogrn, organization_oid, subdivision_oid, region_name, region_oktmo_code, gar_address_id, legal_address, legal_postal_code, email, phone, fax, oms_started_at, registry_included_at, registry_excluded_at, exclusion_reason, valid_from, valid_to)
                    VALUES (line.id, line.parent_uidmo, line.registry_number, line.parent_registry_number, line.medical_org_code, line.name, line.short_name, line.separate_unit_flag, line.medical_org_type, line.departmental_affiliation, line.ownership_code, line.inn, line.kpp, line.ogrn, line.organization_oid, line.subdivision_oid, line.region_name, line.region_oktmo_code, line.gar_address_id, line.legal_address, line.legal_postal_code, line.email, line.phone, line.fax, line.oms_started_at, line.registry_included_at, line.registry_excluded_at, line.exclusion_reason, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_medical_organization SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_medical_organization
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_medical_organization t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_medical_organization r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_medical_organization;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_medical_quality_expert(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_medical_quality_expert';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_medical_quality_expert', 0));
    LOCK TABLE data.dsa_raw_foms_medical_quality_expert IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_medical_quality_expert IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_medical_quality_expert;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_medical_quality_expert;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_medical_quality_expert', 'foms_medical_quality_expert',
        'full', 'dsa_data_load.load_foms_medical_quality_expert', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_medical_quality_expert SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_medical_quality_expert r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_medical_quality_expert t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_medical_quality_expert t SET registry_number = line.registry_number, legacy_expert_code = line.legacy_expert_code, region_oktmo_code = line.region_oktmo_code, region_name = line.region_name, work_phone = line.work_phone, mobile_phone = line.mobile_phone, email = line.email, registry_created_at = line.registry_created_at, registry_excluded_at = line.registry_excluded_at, exclusion_reason = line.exclusion_reason, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_medical_quality_expert (id, registry_number, legacy_expert_code, region_oktmo_code, region_name, work_phone, mobile_phone, email, registry_created_at, registry_excluded_at, exclusion_reason, valid_from, valid_to)
                    VALUES (line.id, line.registry_number, line.legacy_expert_code, line.region_oktmo_code, line.region_name, line.work_phone, line.mobile_phone, line.email, line.registry_created_at, line.registry_excluded_at, line.exclusion_reason, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_medical_quality_expert SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_medical_quality_expert
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_medical_quality_expert t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_medical_quality_expert r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_medical_quality_expert;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_payment_method(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_payment_method';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_payment_method', 0));
    LOCK TABLE data.dsa_raw_foms_payment_method IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_payment_method IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_payment_method;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_payment_method;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_payment_method', 'foms_payment_method',
        'full', 'dsa_data_load.load_foms_payment_method', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_payment_method SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_payment_method r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_payment_method t WHERE t.id = line.id AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_payment_method t SET name = line.name, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_payment_method (id, valid_from, name, valid_to)
                    VALUES (line.id, line.valid_from, line.name, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_payment_method SET new_key = jsonb_build_object('id', line.id, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_payment_method
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_payment_method t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_payment_method r WHERE r.id = t.id AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_payment_method;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_payment_organization_details(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_payment_organization_details';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_payment_organization_details', 0));
    LOCK TABLE data.dsa_raw_foms_payment_organization_details IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_payment_organization_details IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_payment_organization_details;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_payment_organization_details;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_payment_organization_details', 'foms_payment_organization_details',
        'full', 'dsa_data_load.load_foms_payment_organization_details', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_payment_organization_details SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.bill_type_code, r.organization_code, r.region_okato_code) AS source_key_count
            FROM data.dsa_raw_foms_payment_organization_details r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.bill_type_code IS NULL OR line.organization_code IS NULL OR line.region_okato_code IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_payment_organization_details t WHERE t.bill_type_code = line.bill_type_code AND t.organization_code = line.organization_code AND t.region_okato_code = line.region_okato_code) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_payment_organization_details t SET source_record_id = line.source_record_id, inn = line.inn, kpp = line.kpp, account_type = line.account_type, account_number = line.account_number, correspondent_account = line.correspondent_account, bank_name = line.bank_name, bank_bik = line.bank_bik, tofk_code = line.tofk_code, tofk_name = line.tofk_name, tofk_bik = line.tofk_bik, treasury_single_account = line.treasury_single_account, financial_agency_name = line.financial_agency_name, personal_account = line.personal_account, personal_account_purpose = line.personal_account_purpose, personal_account_tofk_code = line.personal_account_tofk_code, income_admin_name = line.income_admin_name, income_admin_inn = line.income_admin_inn, income_admin_kpp = line.income_admin_kpp, personal_account_income_admin = line.personal_account_income_admin, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.bill_type_code = line.bill_type_code AND t.organization_code = line.organization_code AND t.region_okato_code = line.region_okato_code;
                ELSE
                    INSERT INTO data.foms_payment_organization_details (bill_type_code, organization_code, region_okato_code, source_record_id, inn, kpp, account_type, account_number, correspondent_account, bank_name, bank_bik, tofk_code, tofk_name, tofk_bik, treasury_single_account, financial_agency_name, personal_account, personal_account_purpose, personal_account_tofk_code, income_admin_name, income_admin_inn, income_admin_kpp, personal_account_income_admin, valid_from, valid_to)
                    VALUES (line.bill_type_code, line.organization_code, line.region_okato_code, line.source_record_id, line.inn, line.kpp, line.account_type, line.account_number, line.correspondent_account, line.bank_name, line.bank_bik, line.tofk_code, line.tofk_name, line.tofk_bik, line.treasury_single_account, line.financial_agency_name, line.personal_account, line.personal_account_purpose, line.personal_account_tofk_code, line.income_admin_name, line.income_admin_inn, line.income_admin_kpp, line.personal_account_income_admin, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_payment_organization_details SET new_key = jsonb_build_object('bill_type_code', line.bill_type_code, 'organization_code', line.organization_code, 'region_okato_code', line.region_okato_code)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_payment_organization_details
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_payment_organization_details t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_payment_organization_details r WHERE r.bill_type_code = t.bill_type_code AND r.organization_code = t.organization_code AND r.region_okato_code = t.region_okato_code);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_payment_organization_details;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_payment_organization(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_payment_organization';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_payment_organization', 0));
    LOCK TABLE data.dsa_raw_foms_payment_organization IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_payment_organization IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_payment_organization;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_payment_organization;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_payment_organization', 'foms_payment_organization',
        'full', 'dsa_data_load.load_foms_payment_organization', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_payment_organization SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_payment_organization r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_payment_organization t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_payment_organization t SET name = line.name, short_name = line.short_name, organization_type = line.organization_type, territorial_fund_code = line.territorial_fund_code, smo_code = line.smo_code, region_okato_code = line.region_okato_code, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_payment_organization (id, name, short_name, organization_type, territorial_fund_code, smo_code, region_okato_code, valid_from, valid_to)
                    VALUES (line.id, line.name, line.short_name, line.organization_type, line.territorial_fund_code, line.smo_code, line.region_okato_code, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_payment_organization SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_payment_organization
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_payment_organization t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_payment_organization r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_payment_organization;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_payment_refusal_reason(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_payment_refusal_reason';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_payment_refusal_reason', 0));
    LOCK TABLE data.dsa_raw_foms_payment_refusal_reason IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_payment_refusal_reason IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_payment_refusal_reason;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_payment_refusal_reason;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_payment_refusal_reason', 'foms_payment_refusal_reason',
        'full', 'dsa_data_load.load_foms_payment_refusal_reason', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_payment_refusal_reason SET reject_reason = NULL, new_key = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.code, r.name, r.valid_from) AS source_key_count
            FROM data.dsa_raw_foms_payment_refusal_reason r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.code IS NULL OR line.name IS NULL OR line.valid_from IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_payment_refusal_reason t WHERE t.code = line.code AND t.name = line.name AND t.valid_from = line.valid_from) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_payment_refusal_reason t SET refusal_basis = line.refusal_basis, service_comment = line.service_comment, control_type_code = line.control_type_code, penalty_coefficient = line.penalty_coefficient, nonpayment_coefficient = line.nonpayment_coefficient, form_pg_code = line.form_pg_code, valid_to = line.valid_to, is_deleted = 'N' WHERE t.code = line.code AND t.name = line.name AND t.valid_from = line.valid_from;
                ELSE
                    INSERT INTO data.foms_payment_refusal_reason (code, name, valid_from, refusal_basis, service_comment, control_type_code, penalty_coefficient, nonpayment_coefficient, form_pg_code, valid_to)
                    VALUES (line.code, line.name, line.valid_from, line.refusal_basis, line.service_comment, line.control_type_code, line.penalty_coefficient, line.nonpayment_coefficient, line.form_pg_code, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_payment_refusal_reason SET new_key = jsonb_build_object('code', line.code, 'name', line.name, 'valid_from', line.valid_from)
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_payment_refusal_reason
                    SET reject_reason = SQLERRM, new_key = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_payment_refusal_reason t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_payment_refusal_reason r WHERE r.code = t.code AND r.name = t.name AND r.valid_from = t.valid_from);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_payment_refusal_reason;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_surgical_treatment_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_surgical_treatment_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_surgical_treatment_type', 0));
    LOCK TABLE data.dsa_raw_foms_surgical_treatment_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_surgical_treatment_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_surgical_treatment_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_surgical_treatment_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_surgical_treatment_type', 'foms_surgical_treatment_type',
        'full', 'dsa_data_load.load_foms_surgical_treatment_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_surgical_treatment_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_surgical_treatment_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_surgical_treatment_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_surgical_treatment_type t SET name = line.name, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_surgical_treatment_type (id, name, valid_from, valid_to)
                    VALUES (line.id, line.name, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_surgical_treatment_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_surgical_treatment_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_surgical_treatment_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_surgical_treatment_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_surgical_treatment_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_foms_treatment_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'foms_treatment_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.foms_treatment_type', 0));
    LOCK TABLE data.dsa_raw_foms_treatment_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.foms_treatment_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.foms_treatment_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_foms_treatment_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_foms_treatment_type', 'foms_treatment_type',
        'full', 'dsa_data_load.load_foms_treatment_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_foms_treatment_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_foms_treatment_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.foms_treatment_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.foms_treatment_type t SET name = line.name, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.foms_treatment_type (id, name, valid_from, valid_to)
                    VALUES (line.id, line.name, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_foms_treatment_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_foms_treatment_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.foms_treatment_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_foms_treatment_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.foms_treatment_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_high_tech_medical_care_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'high_tech_medical_care_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.high_tech_medical_care_type', 0));
    LOCK TABLE data.dsa_raw_high_tech_medical_care_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.high_tech_medical_care_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.high_tech_medical_care_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_high_tech_medical_care_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_high_tech_medical_care_type', 'high_tech_medical_care_type',
        'full', 'dsa_data_load.load_high_tech_medical_care_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_high_tech_medical_care_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_high_tech_medical_care_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.high_tech_medical_care_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.high_tech_medical_care_type t SET name = line.name, name_id = line.name_id, profile_id = line.profile_id, profile_name = line.profile_name, icd10_code = line.icd10_code, patient_model_id = line.patient_model_id, patient_model = line.patient_model, treatment_type_id = line.treatment_type_id, treatment_type = line.treatment_type, treatment_method_id = line.treatment_method_id, treatment_method = line.treatment_method, vmp_group = line.vmp_group, part = line.part, finance = line.finance, valid_from = line.valid_from, valid_to = line.valid_to, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.high_tech_medical_care_type (id, name, name_id, profile_id, profile_name, icd10_code, patient_model_id, patient_model, treatment_type_id, treatment_type, treatment_method_id, treatment_method, vmp_group, part, finance, valid_from, valid_to, display_order)
                    VALUES (line.id, line.name, line.name_id, line.profile_id, line.profile_name, line.icd10_code, line.patient_model_id, line.patient_model, line.treatment_type_id, line.treatment_type, line.treatment_method_id, line.treatment_method, line.vmp_group, line.part, line.finance, line.valid_from, line.valid_to, line.display_order);
                END IF;
                UPDATE data.dsa_raw_high_tech_medical_care_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_high_tech_medical_care_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.high_tech_medical_care_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_high_tech_medical_care_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.high_tech_medical_care_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_high_tech_patient_model(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'high_tech_patient_model';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.high_tech_patient_model', 0));
    LOCK TABLE data.dsa_raw_high_tech_patient_model IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.high_tech_patient_model IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.high_tech_patient_model;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_high_tech_patient_model;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_high_tech_patient_model', 'high_tech_patient_model',
        'full', 'dsa_data_load.load_high_tech_patient_model', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_high_tech_patient_model SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_high_tech_patient_model r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.high_tech_patient_model t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.high_tech_patient_model t SET name = line.name, sections = line.sections, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.high_tech_patient_model (id, name, sections, valid_from, valid_to)
                    VALUES (line.id, line.name, line.sections, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_high_tech_patient_model SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_high_tech_patient_model
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.high_tech_patient_model t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_high_tech_patient_model r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.high_tech_patient_model;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_high_tech_treatment_method(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'high_tech_treatment_method';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.high_tech_treatment_method', 0));
    LOCK TABLE data.dsa_raw_high_tech_treatment_method IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.high_tech_treatment_method IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.high_tech_treatment_method;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_high_tech_treatment_method;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_high_tech_treatment_method', 'high_tech_treatment_method',
        'full', 'dsa_data_load.load_high_tech_treatment_method', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_high_tech_treatment_method SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_high_tech_treatment_method r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.high_tech_treatment_method t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.high_tech_treatment_method t SET name = line.name, sections = line.sections, implantation_obligation = line.implantation_obligation, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.high_tech_treatment_method (id, name, sections, implantation_obligation, valid_from, valid_to)
                    VALUES (line.id, line.name, line.sections, line.implantation_obligation, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_high_tech_treatment_method SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_high_tech_treatment_method
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.high_tech_treatment_method t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_high_tech_treatment_method r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.high_tech_treatment_method;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_high_tech_treatment_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'high_tech_treatment_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.high_tech_treatment_type', 0));
    LOCK TABLE data.dsa_raw_high_tech_treatment_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.high_tech_treatment_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.high_tech_treatment_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_high_tech_treatment_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_high_tech_treatment_type', 'high_tech_treatment_type',
        'full', 'dsa_data_load.load_high_tech_treatment_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_high_tech_treatment_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_high_tech_treatment_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.high_tech_treatment_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.high_tech_treatment_type t SET name = line.name, valid_from = line.valid_from, valid_to = line.valid_to, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.high_tech_treatment_type (id, name, valid_from, valid_to)
                    VALUES (line.id, line.name, line.valid_from, line.valid_to);
                END IF;
                UPDATE data.dsa_raw_high_tech_treatment_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_high_tech_treatment_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.high_tech_treatment_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_high_tech_treatment_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.high_tech_treatment_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_icd10(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'icd10';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.icd10', 0));
    LOCK TABLE data.dsa_raw_icd10 IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.icd10 IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.icd10;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_icd10;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_icd10', 'icd10',
        'full', 'dsa_data_load.load_icd10', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_icd10 SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_icd10 r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.icd10 t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.icd10 t SET parent_id = line.parent_id, code = line.code, name = line.name, rec_code = line.rec_code, additional_code = line.additional_code, actual = line.actual, actuality_changed_at = line.actuality_changed_at, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.icd10 (id, parent_id, code, name, rec_code, additional_code, actual, actuality_changed_at)
                    VALUES (line.id, line.parent_id, line.code, line.name, line.rec_code, line.additional_code, line.actual, line.actuality_changed_at);
                END IF;
                UPDATE data.dsa_raw_icd10 SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_icd10
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.icd10 t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_icd10 r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.icd10;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_immunobiological_disease_group(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'immunobiological_disease_group';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.immunobiological_disease_group', 0));
    LOCK TABLE data.dsa_raw_immunobiological_disease_group IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.immunobiological_disease_group IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.immunobiological_disease_group;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_immunobiological_disease_group;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_immunobiological_disease_group', 'immunobiological_disease_group',
        'full', 'dsa_data_load.load_immunobiological_disease_group', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_immunobiological_disease_group SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_immunobiological_disease_group r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.immunobiological_disease_group t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.immunobiological_disease_group t SET name = line.name, synonyms = line.synonyms, used_in_elmk = line.used_in_elmk, elmk_name = line.elmk_name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.immunobiological_disease_group (id, name, synonyms, used_in_elmk, elmk_name)
                    VALUES (line.id, line.name, line.synonyms, line.used_in_elmk, line.elmk_name);
                END IF;
                UPDATE data.dsa_raw_immunobiological_disease_group SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_immunobiological_disease_group
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.immunobiological_disease_group t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_immunobiological_disease_group r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.immunobiological_disease_group;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_implantable_assistive_device_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'implantable_assistive_device_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.implantable_assistive_device_type', 0));
    LOCK TABLE data.dsa_raw_implantable_assistive_device_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.implantable_assistive_device_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.implantable_assistive_device_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_implantable_assistive_device_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_implantable_assistive_device_type', 'implantable_assistive_device_type',
        'full', 'dsa_data_load.load_implantable_assistive_device_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_implantable_assistive_device_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_implantable_assistive_device_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.implantable_assistive_device_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.implantable_assistive_device_type t SET parent_id = line.parent_id, name = line.name, rzn_code = line.rzn_code, disease_code = line.disease_code, actual = line.actual, existence_npa = line.existence_npa, source_order = line.source_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.implantable_assistive_device_type (id, parent_id, name, rzn_code, disease_code, actual, existence_npa, source_order)
                    VALUES (line.id, line.parent_id, line.name, line.rzn_code, line.disease_code, line.actual, line.existence_npa, line.source_order);
                END IF;
                UPDATE data.dsa_raw_implantable_assistive_device_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_implantable_assistive_device_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.implantable_assistive_device_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_implantable_assistive_device_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.implantable_assistive_device_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_injury_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'injury_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.injury_type', 0));
    LOCK TABLE data.dsa_raw_injury_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.injury_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.injury_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_injury_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_injury_type', 'injury_type',
        'full', 'dsa_data_load.load_injury_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_injury_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_injury_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.injury_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.injury_type t SET name = line.name, form_066u_02_code = line.form_066u_02_code, form_066u_02_name = line.form_066u_02_name, form_025u_1_code = line.form_025u_1_code, form_025u_1_name = line.form_025u_1_name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.injury_type (id, name, form_066u_02_code, form_066u_02_name, form_025u_1_code, form_025u_1_name)
                    VALUES (line.id, line.name, line.form_066u_02_code, line.form_066u_02_name, line.form_025u_1_code, line.form_025u_1_name);
                END IF;
                UPDATE data.dsa_raw_injury_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_injury_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.injury_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_injury_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.injury_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_laboratory_specimen(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'laboratory_specimen';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.laboratory_specimen', 0));
    LOCK TABLE data.dsa_raw_laboratory_specimen IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.laboratory_specimen IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.laboratory_specimen;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_laboratory_specimen;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_laboratory_specimen', 'laboratory_specimen',
        'full', 'dsa_data_load.load_laboratory_specimen', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_laboratory_specimen SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_laboratory_specimen r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.laboratory_specimen t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.laboratory_specimen t SET specimen_group = line.specimen_group, material_id = line.material_id, material_name = line.material_name, name = line.name, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.laboratory_specimen (id, specimen_group, material_id, material_name, name, display_order)
                    VALUES (line.id, line.specimen_group, line.material_id, line.material_name, line.name, line.display_order);
                END IF;
                UPDATE data.dsa_raw_laboratory_specimen SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_laboratory_specimen
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.laboratory_specimen t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_laboratory_specimen r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.laboratory_specimen;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_laboratory_test(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'laboratory_test';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.laboratory_test', 0));
    LOCK TABLE data.dsa_raw_laboratory_test IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.laboratory_test IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.laboratory_test;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_laboratory_test;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_laboratory_test', 'laboratory_test',
        'full', 'dsa_data_load.load_laboratory_test', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_laboratory_test SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_laboratory_test r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.laboratory_test t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.laboratory_test t SET name = line.name, short_name = line.short_name, english_name = line.english_name, synonyms = line.synonyms, loinc_code = line.loinc_code, analyte = line.analyte, analyte_characteristic = line.analyte_characteristic, measurement = line.measurement, unit = line.unit, specimen = line.specimen, time_characteristic = line.time_characteristic, method_type = line.method_type, scale_type = line.scale_type, test_status = line.test_status, test_group = line.test_group, nmu_codes = line.nmu_codes, source_order = line.source_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.laboratory_test (id, name, short_name, english_name, synonyms, loinc_code, analyte, analyte_characteristic, measurement, unit, specimen, time_characteristic, method_type, scale_type, test_status, test_group, nmu_codes, source_order)
                    VALUES (line.id, line.name, line.short_name, line.english_name, line.synonyms, line.loinc_code, line.analyte, line.analyte_characteristic, line.measurement, line.unit, line.specimen, line.time_characteristic, line.method_type, line.scale_type, line.test_status, line.test_group, line.nmu_codes, line.source_order);
                END IF;
                UPDATE data.dsa_raw_laboratory_test SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_laboratory_test
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.laboratory_test t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_laboratory_test r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.laboratory_test;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_laterality(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'laterality';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.laterality', 0));
    LOCK TABLE data.dsa_raw_laterality IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.laterality IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.laterality;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_laterality;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_laterality', 'laterality',
        'full', 'dsa_data_load.load_laterality', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_laterality SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_laterality r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.laterality t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.laterality t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.laterality (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_laterality SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_laterality
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.laterality t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_laterality r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.laterality;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_measurement_unit(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'measurement_unit';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.measurement_unit', 0));
    LOCK TABLE data.dsa_raw_measurement_unit IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.measurement_unit IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.measurement_unit;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_measurement_unit;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_measurement_unit', 'measurement_unit',
        'full', 'dsa_data_load.load_measurement_unit', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_measurement_unit SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_measurement_unit r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.measurement_unit t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.measurement_unit t SET name = line.name, short_name = line.short_name, print_name = line.print_name, measurement = line.measurement, ucum_code = line.ucum_code, coefficient = line.coefficient, formula = line.formula, conversion_unit_id = line.conversion_unit_id, conversion_unit_name = line.conversion_unit_name, okei_code = line.okei_code, eec_dictionary_code = line.eec_dictionary_code, eec_element_code = line.eec_element_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.measurement_unit (id, name, short_name, print_name, measurement, ucum_code, coefficient, formula, conversion_unit_id, conversion_unit_name, okei_code, eec_dictionary_code, eec_element_code)
                    VALUES (line.id, line.name, line.short_name, line.print_name, line.measurement, line.ucum_code, line.coefficient, line.formula, line.conversion_unit_id, line.conversion_unit_name, line.okei_code, line.eec_dictionary_code, line.eec_element_code);
                END IF;
                UPDATE data.dsa_raw_measurement_unit SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_measurement_unit
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.measurement_unit t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_measurement_unit r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.measurement_unit;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_care_condition(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_care_condition';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_care_condition', 0));
    LOCK TABLE data.dsa_raw_medical_care_condition IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_care_condition IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_care_condition;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_care_condition;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_care_condition', 'medical_care_condition',
        'full', 'dsa_data_load.load_medical_care_condition', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_care_condition SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_care_condition r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_care_condition t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_care_condition t SET name = line.name, oms_condition_code = line.oms_condition_code, comments = line.comments, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_care_condition (id, name, oms_condition_code, comments)
                    VALUES (line.id, line.name, line.oms_condition_code, line.comments);
                END IF;
                UPDATE data.dsa_raw_medical_care_condition SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_care_condition
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_care_condition t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_care_condition r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_care_condition;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_care_form(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_care_form';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_care_form', 0));
    LOCK TABLE data.dsa_raw_medical_care_form IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_care_form IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_care_form;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_care_form;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_care_form', 'medical_care_form',
        'full', 'dsa_data_load.load_medical_care_form', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_care_form SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_care_form r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_care_form t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_care_form t SET name = line.name, oms_care_form_code = line.oms_care_form_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_care_form (id, name, oms_care_form_code)
                    VALUES (line.id, line.name, line.oms_care_form_code);
                END IF;
                UPDATE data.dsa_raw_medical_care_form SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_care_form
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_care_form t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_care_form r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_care_form;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_care_location(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_care_location';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_care_location', 0));
    LOCK TABLE data.dsa_raw_medical_care_location IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_care_location IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_care_location;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_care_location;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_care_location', 'medical_care_location',
        'full', 'dsa_data_load.load_medical_care_location', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_care_location SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_care_location r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_care_location t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_care_location t SET name = line.name, form_025_1y_flag = line.form_025_1y_flag, oms_visit_place_code = line.oms_visit_place_code, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_care_location (id, name, form_025_1y_flag, oms_visit_place_code, display_order)
                    VALUES (line.id, line.name, line.form_025_1y_flag, line.oms_visit_place_code, line.display_order);
                END IF;
                UPDATE data.dsa_raw_medical_care_location SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_care_location
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_care_location t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_care_location r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_care_location;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_care_profile(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_care_profile';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_care_profile', 0));
    LOCK TABLE data.dsa_raw_medical_care_profile IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_care_profile IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_care_profile;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_care_profile;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_care_profile', 'medical_care_profile',
        'full', 'dsa_data_load.load_medical_care_profile', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_care_profile SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_care_profile r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_care_profile t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_care_profile t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_care_profile (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_medical_care_profile SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_care_profile
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_care_profile t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_care_profile r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_care_profile;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_care_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_care_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_care_type', 0));
    LOCK TABLE data.dsa_raw_medical_care_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_care_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_care_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_care_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_care_type', 'medical_care_type',
        'full', 'dsa_data_load.load_medical_care_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_care_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_care_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_care_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_care_type t SET parent_id = line.parent_id, name = line.name, oms_care_type_code = line.oms_care_type_code, display_order = line.display_order, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_care_type (id, parent_id, name, oms_care_type_code, display_order)
                    VALUES (line.id, line.parent_id, line.name, line.oms_care_type_code, line.display_order);
                END IF;
                UPDATE data.dsa_raw_medical_care_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_care_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_care_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_care_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_care_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_equipment_type(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_equipment_type';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_equipment_type', 0));
    LOCK TABLE data.dsa_raw_medical_equipment_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_equipment_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_equipment_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_equipment_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_equipment_type', 'medical_equipment_type',
        'full', 'dsa_data_load.load_medical_equipment_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_equipment_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_equipment_type r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_equipment_type t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_equipment_type t SET parent_id = line.parent_id, name = line.name, available = line.available, abolished_at = line.abolished_at, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_equipment_type (id, parent_id, name, available, abolished_at)
                    VALUES (line.id, line.parent_id, line.name, line.available, line.abolished_at);
                END IF;
                UPDATE data.dsa_raw_medical_equipment_type SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_equipment_type
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_equipment_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_equipment_type r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_equipment_type;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_position(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_position';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_position', 0));
    LOCK TABLE data.dsa_raw_medical_position IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_position IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_position;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_position;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_position', 'medical_position',
        'full', 'dsa_data_load.load_medical_position', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_position SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_position r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_position t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_position t SET parent_id = line.parent_id, name = line.name, equivalent = line.equivalent, display_order = line.display_order, normative_id = line.normative_id, group_flag = line.group_flag, form_30 = line.form_30, actual = line.actual, end_date = line.end_date, comment = line.comment, need_qual = line.need_qual, zs = line.zs, need_cert = line.need_cert, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_position (id, parent_id, name, equivalent, display_order, normative_id, group_flag, form_30, actual, end_date, comment, need_qual, zs, need_cert)
                    VALUES (line.id, line.parent_id, line.name, line.equivalent, line.display_order, line.normative_id, line.group_flag, line.form_30, line.actual, line.end_date, line.comment, line.need_qual, line.zs, line.need_cert);
                END IF;
                UPDATE data.dsa_raw_medical_position SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_position
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_position t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_position r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_position;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_service(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_service';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_service', 0));
    LOCK TABLE data.dsa_raw_medical_service IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_service IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_service;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_service;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_service', 'medical_service',
        'full', 'dsa_data_load.load_medical_service', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_service SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_service r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_service t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_service t SET code = line.code, name = line.name, relevance = line.relevance, abolished_at = line.abolished_at, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_service (id, code, name, relevance, abolished_at)
                    VALUES (line.id, line.code, line.name, line.relevance, line.abolished_at);
                END IF;
                UPDATE data.dsa_raw_medical_service SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_service
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_service t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_service r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_service;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_specialty(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_specialty';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_specialty', 0));
    LOCK TABLE data.dsa_raw_medical_specialty IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_specialty IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_specialty;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_specialty;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_specialty', 'medical_specialty',
        'full', 'dsa_data_load.load_medical_specialty', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_specialty SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_specialty r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_specialty t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_specialty t SET parent_id = line.parent_id, name = line.name, relevance = line.relevance, abolished_at = line.abolished_at, ffoms_code = line.ffoms_code, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_specialty (id, parent_id, name, relevance, abolished_at, ffoms_code)
                    VALUES (line.id, line.parent_id, line.name, line.relevance, line.abolished_at, line.ffoms_code);
                END IF;
                UPDATE data.dsa_raw_medical_specialty SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_specialty
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_specialty t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_specialty r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_specialty;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_visit_reason(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_visit_reason';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_visit_reason', 0));
    LOCK TABLE data.dsa_raw_medical_visit_reason IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_visit_reason IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_visit_reason;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_visit_reason;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_visit_reason', 'medical_visit_reason',
        'full', 'dsa_data_load.load_medical_visit_reason', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_visit_reason SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_visit_reason r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_visit_reason t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_visit_reason t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_visit_reason (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_medical_visit_reason SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_visit_reason
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_visit_reason t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_visit_reason r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_visit_reason;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_medical_visit_result(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'medical_visit_result';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.medical_visit_result', 0));
    LOCK TABLE data.dsa_raw_medical_visit_result IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.medical_visit_result IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.medical_visit_result;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_medical_visit_result;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_medical_visit_result', 'medical_visit_result',
        'full', 'dsa_data_load.load_medical_visit_result', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_medical_visit_result SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_medical_visit_result r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.medical_visit_result t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.medical_visit_result t SET name = line.name, form_025_code = line.form_025_code, form_066_02_code = line.form_066_02_code, form_066_02_name = line.form_066_02_name, form_066_u_code = line.form_066_u_code, form_066_u_name = line.form_066_u_name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.medical_visit_result (id, name, form_025_code, form_066_02_code, form_066_02_name, form_066_u_code, form_066_u_name)
                    VALUES (line.id, line.name, line.form_025_code, line.form_066_02_code, line.form_066_02_name, line.form_066_u_code, line.form_066_u_name);
                END IF;
                UPDATE data.dsa_raw_medical_visit_result SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_medical_visit_result
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.medical_visit_result t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_medical_visit_result r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.medical_visit_result;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_outpatient_visit_purpose(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'outpatient_visit_purpose';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.outpatient_visit_purpose', 0));
    LOCK TABLE data.dsa_raw_outpatient_visit_purpose IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.outpatient_visit_purpose IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.outpatient_visit_purpose;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_outpatient_visit_purpose;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_outpatient_visit_purpose', 'outpatient_visit_purpose',
        'full', 'dsa_data_load.load_outpatient_visit_purpose', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_outpatient_visit_purpose SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_outpatient_visit_purpose r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.outpatient_visit_purpose t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.outpatient_visit_purpose t SET name = line.name, invisible = line.invisible, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.outpatient_visit_purpose (id, name, invisible)
                    VALUES (line.id, line.name, line.invisible);
                END IF;
                UPDATE data.dsa_raw_outpatient_visit_purpose SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_outpatient_visit_purpose
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.outpatient_visit_purpose t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_outpatient_visit_purpose r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.outpatient_visit_purpose;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_patient_sex(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'patient_sex';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.patient_sex', 0));
    LOCK TABLE data.dsa_raw_patient_sex IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.patient_sex IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.patient_sex;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_patient_sex;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_patient_sex', 'patient_sex',
        'full', 'dsa_data_load.load_patient_sex', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_patient_sex SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_patient_sex r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.patient_sex t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.patient_sex t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.patient_sex (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_patient_sex SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_patient_sex
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.patient_sex t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_patient_sex r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.patient_sex;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_tnm_staging(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'tnm_staging';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.tnm_staging', 0));
    LOCK TABLE data.dsa_raw_tnm_staging IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.tnm_staging IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.tnm_staging;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_tnm_staging;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_tnm_staging', 'tnm_staging',
        'full', 'dsa_data_load.load_tnm_staging', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_tnm_staging SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_tnm_staging r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.tnm_staging t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.tnm_staging t SET topography_name = line.topography_name, icdo_topography = line.icdo_topography, morphology = line.morphology, stage = line.stage, tumor = line.tumor, tumor_category_id = line.tumor_category_id, nodus = line.nodus, nodus_category_id = line.nodus_category_id, metastasis = line.metastasis, metastasis_category_id = line.metastasis_category_id, addition = line.addition, addition_category_id = line.addition_category_id, classification = line.classification, tnm_version = line.tnm_version, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.tnm_staging (id, topography_name, icdo_topography, morphology, stage, tumor, tumor_category_id, nodus, nodus_category_id, metastasis, metastasis_category_id, addition, addition_category_id, classification, tnm_version)
                    VALUES (line.id, line.topography_name, line.icdo_topography, line.morphology, line.stage, line.tumor, line.tumor_category_id, line.nodus, line.nodus_category_id, line.metastasis, line.metastasis_category_id, line.addition, line.addition_category_id, line.classification, line.tnm_version);
                END IF;
                UPDATE data.dsa_raw_tnm_staging SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_tnm_staging
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.tnm_staging t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_tnm_staging r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.tnm_staging;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_unlawful_harm_sign(
    pUserId bigint,
    pVersion varchar(100),
    pDataSourceURL varchar(500), INOUT p_batch_id bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    userName varchar(100);
    logLevelInfoId bigint;
    logLevelWarningId bigint;
    loadBatchId bigint;
    currentVersion varchar(100);
    entityName constant varchar(100) := 'unlawful_harm_sign';
    rowsCurrent bigint;
    rowsCurrentDeleted bigint;
    rowsExtracted bigint;
    rowsRejected bigint := 0;
    rowsInserted bigint := 0;
    rowsUpdated bigint := 0;
    rowsDeleted bigint := 0;
    rowsNew bigint;
    rowsNewDeleted bigint;
    finalStatus varchar(20);
    line record;
    rowExists boolean;
BEGIN
    IF pUserId IS NULL OR nullif(btrim(pVersion), '') IS NULL
        OR nullif(btrim(pDataSourceURL), '') IS NULL THEN
        RAISE EXCEPTION 'userId, version and source URL are required';
    END IF;
    IF length(pVersion) > 100 OR length(pDataSourceURL) > 500 THEN
        RAISE EXCEPTION 'version or source URL exceeds the supported length';
    END IF;

    -- Serialize applications of this dictionary, including reading its version.
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.unlawful_harm_sign', 0));
    LOCK TABLE data.dsa_raw_unlawful_harm_sign IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.unlawful_harm_sign IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.unlawful_harm_sign;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_unlawful_harm_sign;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_unlawful_harm_sign', 'unlawful_harm_sign',
        'full', 'dsa_data_load.load_unlawful_harm_sign', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_unlawful_harm_sign SET reject_reason = NULL, new_id = NULL;
        FOR line IN
            SELECT r.*, count(*) OVER (PARTITION BY r.id) AS source_key_count
            FROM data.dsa_raw_unlawful_harm_sign r ORDER BY raw_row_id
        LOOP
            BEGIN
                IF line.id IS NULL THEN
                    RAISE EXCEPTION 'Source key must not be null';
                END IF;
                IF line.source_key_count > 1 THEN
                    RAISE EXCEPTION 'Duplicate source key';
                END IF;
                SELECT EXISTS(SELECT 1 FROM data.unlawful_harm_sign t WHERE t.id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.unlawful_harm_sign t SET name = line.name, is_deleted = 'N' WHERE t.id = line.id;
                ELSE
                    INSERT INTO data.unlawful_harm_sign (id, name)
                    VALUES (line.id, line.name);
                END IF;
                UPDATE data.dsa_raw_unlawful_harm_sign SET new_id = line.id
                    WHERE raw_row_id = line.raw_row_id;
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_unlawful_harm_sign
                    SET reject_reason = SQLERRM, new_id = NULL
                    WHERE raw_row_id = line.raw_row_id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.unlawful_harm_sign t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_unlawful_harm_sign r WHERE r.id = t.id);
            GET DIAGNOSTICS rowsDeleted = ROW_COUNT;
            INSERT INTO data.dsa_loaded_version(entity_name, version, data_source, data_source_url, load_date)
                VALUES (entityName, pVersion, 'minzdrav', pDataSourceURL, now())
                ON CONFLICT (entity_name) DO UPDATE SET
                    version = excluded.version,
                    data_source = excluded.data_source,
                    data_source_url = excluded.data_source_url,
                    load_date = excluded.load_date;
            finalStatus := 'success';
        ELSE
            finalStatus := 'partial';
        END IF;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsNew, rowsNewDeleted FROM data.unlawful_harm_sign;
    UPDATE data.dsa_load_batch SET
        finished_at = clock_timestamp(), status = finalStatus,
        rows_rejected = rowsRejected, rows_inserted = rowsInserted,
        rows_updated = rowsUpdated, rows_deleted = rowsDeleted,
        rows_new = rowsNew, rows_new_deleted = rowsNewDeleted,
        error_message = CASE
            WHEN rowsExtracted = 0 THEN 'Пустые входные данные'
            WHEN rowsRejected > 0 THEN 'Есть отклоненные записи; версия не обновлена'
            ELSE NULL
        END
        WHERE id = loadBatchId;

    INSERT INTO data.system_log(log_date, log_level_id, record_details)
        VALUES (
            now(),
            CASE WHEN finalStatus = 'success' THEN logLevelInfoId ELSE logLevelWarningId END,
            format('Загрузка данных %s: статус %s, отклонено записей %s',
                   loadBatchId, finalStatus, rowsRejected)
        );
END;
$$;

