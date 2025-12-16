-- Cursor for waiting patients
DECLARE
    CURSOR waiting_patients_cursor IS
        SELECT 
            pq.queue_id,
            p.first_name || ' ' || p.last_name AS patient_name,
            sr.room_name,
            pq.queue_position,
            ROUND(EXTRACT(DAY FROM (SYSDATE - pq.time_entered_queue)) * 24 * 60 + 
                  EXTRACT(HOUR FROM (SYSDATE - pq.time_entered_queue)) * 60 +
                  EXTRACT(MINUTE FROM (SYSDATE - pq.time_entered_queue)), 1) AS wait_minutes
        FROM patient_queue pq
        JOIN patients p ON pq.patient_id = p.patient_id
        JOIN service_rooms sr ON pq.room_id = sr.room_id
        WHERE pq.status = 'waiting'
        ORDER BY pq.room_id, pq.queue_position;
    
    v_queue_id patient_queue.queue_id%TYPE;
    v_patient_name VARCHAR2(101);
    v_room_name service_rooms.room_name%TYPE;
    v_position patient_queue.queue_position%TYPE;
    v_wait_minutes NUMBER;
    v_counter NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== WAITING PATIENTS REPORT ===');
    DBMS_OUTPUT.PUT_LINE('Generated: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI'));
    DBMS_OUTPUT.PUT_LINE('');
    
    OPEN waiting_patients_cursor;
    
    LOOP
        FETCH waiting_patients_cursor INTO v_queue_id, v_patient_name, v_room_name, v_position, v_wait_minutes;
        EXIT WHEN waiting_patients_cursor%NOTFOUND;
        
        v_counter := v_counter + 1;
        
        DBMS_OUTPUT.PUT_LINE(
            'Queue ID: ' || v_queue_id || 
            ' | Patient: ' || RPAD(v_patient_name, 25) ||
            ' | Room: ' || RPAD(v_room_name, 15) ||
            ' | Position: ' || v_position ||
            ' | Wait: ' || v_wait_minutes || ' min'
        );
    END LOOP;
    
    CLOSE waiting_patients_cursor;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Total waiting patients: ' || v_counter);
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        IF waiting_patients_cursor%ISOPEN THEN
            CLOSE waiting_patients_cursor;
        END IF;
END;
/

-- Cursor with parameter for room-specific queue
DECLARE
    CURSOR room_queue_cursor(p_room_id NUMBER) IS
        SELECT 
            pq.queue_id,
            p.first_name || ' ' || p.last_name AS patient_name,
            pq.queue_position,
            pq.status,
            TO_CHAR(pq.time_entered_queue, 'HH24:MI') AS entered_time
        FROM patient_queue pq
        JOIN patients p ON pq.patient_id = p.patient_id
        WHERE pq.room_id = p_room_id
        ORDER BY pq.queue_position;
    
    TYPE queue_rec IS RECORD (
        queue_id NUMBER,
        patient_name VARCHAR2(101),
        position NUMBER,
        status VARCHAR2(20),
        entered_time VARCHAR2(5)
    );
    
    v_record queue_rec;
    v_room_id NUMBER := 1; -- Example: Room 1
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ROOM QUEUE FOR ROOM ' || v_room_id || ' ===');
    
    OPEN room_queue_cursor(v_room_id);
    
    LOOP
        FETCH room_queue_cursor INTO v_record;
        EXIT WHEN room_queue_cursor%NOTFOUND;
        
        DBMS_OUTPUT.PUT_LINE(
            'Pos ' || v_record.position || ': ' ||
            RPAD(v_record.patient_name, 25) ||
            ' | Status: ' || RPAD(v_record.status, 12) ||
            ' | Entered: ' || v_record.entered_time ||
            ' | ID: ' || v_record.queue_id
        );
    END LOOP;
    
    CLOSE room_queue_cursor;
    
    DBMS_OUTPUT.PUT_LINE('End of queue list.');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        IF room_queue_cursor%ISOPEN THEN
            CLOSE room_queue_cursor;
        END IF;
END;
/

-- Cursor with FOR loop (simpler syntax)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TODAY''S COMPLETED SERVICES ===');
    DBMS_OUTPUT.PUT_LINE('');
    
    FOR rec IN (
        SELECT 
            sr.service_type,
            COUNT(*) AS service_count,
            CASE 
                WHEN AVG(
                    CASE WHEN pq.status = 'completed' THEN
                        (pq.check_out_time - pq.check_in_time) * 24 * 60
                    END
                ) IS NULL THEN 0
                ELSE ROUND(AVG(
                    CASE WHEN pq.status = 'completed' THEN
                        (pq.check_out_time - pq.check_in_time) * 24 * 60
                    END
                ), 1)
            END AS avg_duration_minutes
        FROM service_requests sr
        LEFT JOIN patient_queue pq ON sr.patient_id = pq.patient_id 
            AND sr.room_id = pq.room_id
        WHERE TRUNC(sr.requested_at) = TRUNC(SYSDATE)
        GROUP BY sr.service_type
        ORDER BY service_count DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(rec.service_type, 25) || ': ' ||
            rec.service_count || ' services | ' ||
            rec.avg_duration_minutes || ' min avg'
        );
    END LOOP;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- Cursor for bulk processing
DECLARE
    CURSOR old_waiting_cursor IS
        SELECT queue_id, patient_id, room_id
        FROM patient_queue
        WHERE status = 'waiting'
        AND time_entered_queue < SYSDATE - INTERVAL '120' MINUTE
        FOR UPDATE; -- Lock rows for update
    
    TYPE id_table IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_queue_ids id_table;
    v_patient_ids id_table;
    v_room_ids id_table;
    v_update_count NUMBER := 0;
BEGIN
    -- Open cursor and fetch all data
    OPEN old_waiting_cursor;
    
    FETCH old_waiting_cursor 
    BULK COLLECT INTO v_queue_ids, v_patient_ids, v_room_ids;
    
    CLOSE old_waiting_cursor;
    
    -- Process in bulk if any records found
    IF v_queue_ids.COUNT > 0 THEN
        -- Bulk update
        FORALL i IN 1..v_queue_ids.COUNT
            UPDATE patient_queue
            SET status = 'skipped',
                check_out_time = SYSTIMESTAMP
            WHERE queue_id = v_queue_ids(i);
        
        v_update_count := SQL%ROWCOUNT;
        
        -- Bulk insert into movement log
        FORALL i IN 1..v_queue_ids.COUNT
            INSERT INTO movement_log (move_id, patient_id, room_id, move_time, action, queue_id)
            VALUES (move_seq.NEXTVAL, v_patient_ids(i), v_room_ids(i), SYSTIMESTAMP, 'redirected', v_queue_ids(i));
        
        COMMIT;
        
        DBMS_OUTPUT.PUT_LINE('Updated ' || v_update_count || ' old waiting records to skipped.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('No old waiting records found.');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in bulk processing: ' || SQLERRM);
        ROLLBACK;
END;
/

-- cursor for patient statistics by age group
DECLARE
    CURSOR patient_stats_cursor IS
        SELECT 
            age_group,
            gender,
            patient_count,
            ROUND(patient_count * 100.0 / total_patients, 1) AS percentage
        FROM (
            SELECT 
                CASE 
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 < 18 THEN 'Under 18'
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 BETWEEN 18 AND 35 THEN '18-35'
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 BETWEEN 36 AND 55 THEN '36-55'
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 BETWEEN 56 AND 70 THEN '56-70'
                    ELSE 'Over 70'
                END AS age_group,
                p.gender,
                COUNT(*) AS patient_count,
                SUM(COUNT(*)) OVER () AS total_patients
            FROM patients p
            GROUP BY 
                CASE 
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 < 18 THEN 'Under 18'
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 BETWEEN 18 AND 35 THEN '18-35'
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 BETWEEN 36 AND 55 THEN '36-55'
                    WHEN MONTHS_BETWEEN(SYSDATE, p.birth_date) / 12 BETWEEN 56 AND 70 THEN '56-70'
                    ELSE 'Over 70'
                END,
                p.gender
        )
        ORDER BY age_group, gender;
    
    v_age_group VARCHAR2(20);
    v_gender VARCHAR2(10);
    v_count NUMBER;
    v_percentage NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== PATIENT DEMOGRAPHICS BY AGE GROUP ===');
    DBMS_OUTPUT.PUT_LINE('');
    
    OPEN patient_stats_cursor;
    
    LOOP
        FETCH patient_stats_cursor INTO v_age_group, v_gender, v_count, v_percentage;
        EXIT WHEN patient_stats_cursor%NOTFOUND;
        
        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_age_group, 10) || ' | ' ||
            RPAD(v_gender, 10) || ' | ' ||
            LPAD(v_count, 5) || ' patients | ' ||
            LPAD(v_percentage, 5) || '%'
        );
    END LOOP;
    
    CLOSE patient_stats_cursor;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        IF patient_stats_cursor%ISOPEN THEN
            CLOSE patient_stats_cursor;
        END IF;
END;
/

-- Cursor for service request analysis
DECLARE
    CURSOR service_analysis_cursor(p_days NUMBER) IS
        SELECT 
            sr.service_type,
            sr.priority,
            COUNT(*) AS request_count,
            SUM(CASE WHEN sr.service_status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
            ROUND(
                SUM(CASE WHEN sr.service_status = 'completed' THEN 1 ELSE 0 END) * 100.0 / 
                NULLIF(COUNT(*), 0), 
                1
            ) AS completion_rate
        FROM service_requests sr
        WHERE sr.requested_at >= TRUNC(SYSDATE) - p_days
        GROUP BY sr.service_type, sr.priority
        ORDER BY request_count DESC;
    
    v_service_type VARCHAR2(50);
    v_priority VARCHAR2(10);
    v_request_count NUMBER;
    v_completed_count NUMBER;
    v_completion_rate NUMBER;
    v_total_requests NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== SERVICE REQUEST ANALYSIS (Last 7 Days) ===');
    DBMS_OUTPUT.PUT_LINE('');
    
    OPEN service_analysis_cursor(7);
    
    LOOP
        FETCH service_analysis_cursor INTO v_service_type, v_priority, v_request_count, v_completed_count, v_completion_rate;
        EXIT WHEN service_analysis_cursor%NOTFOUND;
        
        v_total_requests := v_total_requests + v_request_count;
        
        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_service_type, 25) || ' | ' ||
            RPAD(v_priority, 8) || ' | ' ||
            LPAD(v_request_count, 4) || ' requests | ' ||
            LPAD(v_completed_count, 4) || ' completed | ' ||
            LPAD(v_completion_rate, 5) || '% rate'
        );
    END LOOP;
    
    CLOSE service_analysis_cursor;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Total requests in last 7 days: ' || v_total_requests);
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        IF service_analysis_cursor%ISOPEN THEN
            CLOSE service_analysis_cursor;
        END IF;
END;
/