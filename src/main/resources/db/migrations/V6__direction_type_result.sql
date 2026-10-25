-- External dependencies (provided by the host system):
-- access_work.users_v(id, full_name)
-- data.log_level(id, sys_name)
-- data.system_log(log_date, log_level_id, record_details)
CREATE OR REPLACE PROCEDURE dsa_data_load.load_direction_type(
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
    entityName constant varchar(100) := 'direction_type';
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
    PERFORM pg_advisory_xact_lock(hashtextextended('dsa_data_load.direction_type', 0));
    LOCK TABLE data.dsa_raw_direction_type IN SHARE ROW EXCLUSIVE MODE;
    LOCK TABLE data.direction_type IN SHARE ROW EXCLUSIVE MODE;

    -- Missing/ambiguous external reference data aborts before changing dictionaries.
    SELECT full_name INTO STRICT userName FROM access_work.users_v WHERE id = pUserId;
    SELECT id INTO STRICT logLevelInfoId FROM data.log_level WHERE lower(sys_name) = 'info';
    SELECT id INTO STRICT logLevelWarningId FROM data.log_level WHERE lower(sys_name) = 'warning';
    IF userName IS NULL THEN
        RAISE EXCEPTION 'User % has no full name', pUserId;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE is_deleted = 'Y')
        INTO rowsCurrent, rowsCurrentDeleted FROM data.direction_type;
    SELECT count(*) INTO rowsExtracted FROM data.dsa_raw_direction_type;
    SELECT version INTO currentVersion
        FROM data.dsa_loaded_version WHERE entity_name = entityName;

    INSERT INTO data.dsa_load_batch (
        data_source, data_source_url, entity_name, dsa_table_name, data_table_name,
        load_type, load_procedure_name, current_version, new_version, loaded_by,
        status, rows_current, rows_current_deleted, rows_extracted
    ) VALUES (
        'minzdrav', pDataSourceURL, entityName, 'dsa_raw_direction_type', 'direction_type',
        'full', 'dsa_data_load.load_direction_type', currentVersion, pVersion, userName,
        'in_progress', rowsCurrent, rowsCurrentDeleted, rowsExtracted
    ) RETURNING id INTO loadBatchId;
    p_batch_id := loadBatchId;

    IF rowsExtracted = 0 THEN
        finalStatus := 'error';
    ELSE
        UPDATE data.dsa_raw_direction_type SET reject_reason = NULL, new_id = NULL;
        FOR line IN SELECT id, name, doc, sort FROM data.dsa_raw_direction_type ORDER BY id LOOP
            BEGIN
                SELECT EXISTS(SELECT 1 FROM data.direction_type WHERE id = line.id) INTO rowExists;
                IF rowExists THEN
                    UPDATE data.direction_type
                        SET name = line.name, display_order = line.sort, is_deleted = 'N'
                        WHERE id = line.id;
                ELSE
                    INSERT INTO data.direction_type(id, name, display_order)
                        VALUES (line.id, line.name, line.sort);
                END IF;
                UPDATE data.dsa_raw_direction_type SET new_id = line.id WHERE id = line.id;
                -- Increment only after all writes for this row have succeeded.
                IF rowExists THEN
                    rowsUpdated := rowsUpdated + 1;
                ELSE
                    rowsInserted := rowsInserted + 1;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                rowsRejected := rowsRejected + 1;
                UPDATE data.dsa_raw_direction_type
                    SET reject_reason = left(SQLERRM, 100), new_id = NULL WHERE id = line.id;
            END;
        END LOOP;

        -- A rejected row must not deactivate its previously loaded counterpart.
        -- Deletions are applied only for a fully accepted snapshot.
        IF rowsRejected = 0 THEN
            UPDATE data.direction_type t SET is_deleted = 'Y'
                WHERE t.is_deleted = 'N'
                  AND NOT EXISTS (SELECT 1 FROM data.dsa_raw_direction_type r WHERE r.id = t.id);
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
        INTO rowsNew, rowsNewDeleted FROM data.direction_type;
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

