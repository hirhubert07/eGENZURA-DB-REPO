-- Procedure for adding a new patient into the system

create or replace PROCEDURE add_patient_proc(
    p_first_name IN VARCHAR2,
    p_last_name IN VARCHAR2,
    p_birth_date IN DATE,
    p_gender IN VARCHAR2,
    p_address IN VARCHAR2 DEFAULT NULL,
    p_phone IN VARCHAR2 DEFAULT NULL,
    p_insurance IN VARCHAR2 DEFAULT NULL,
    p_patient_id OUT NUMBER
) IS

BEGIN
    -- Validate gender
    IF p_gender NOT IN ('M', 'F', 'Other') THEN
        RAISE_APPLICATION_ERROR(-20001, 'Gender must be M, F, or Other');
    END IF;

    -- Check if phone already exists
    IF p_phone IS NOT NULL THEN
        DECLARE
            v_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_count 
            FROM patients 
            WHERE phone_number = p_phone;

            IF v_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20002, 'Phone number already exists');
            END IF;
        END;
    END IF;

    -- Insert patient using sequence
    INSERT INTO patients (patient_id, first_name, last_name, birth_date, gender, address, phone_number, medical_insurance)
    VALUES (patient_seq.NEXTVAL, p_first_name, p_last_name, p_birth_date, p_gender, p_address, p_phone, p_insurance)
    RETURNING patient_id INTO p_patient_id;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Patient added successfully. ID: ' || p_patient_id);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_patient_proc;


-- Procedure for adding a patient to queue

create or replace PROCEDURE add_to_queue_proc(
    p_patient_id IN NUMBER,
    p_room_id IN NUMBER,
    p_queue_id OUT NUMBER
)
IS
    v_next_position NUMBER;
    v_patient_count NUMBER;
    v_room_count NUMBER;
BEGIN
    -- Check if patient exists
    SELECT COUNT(*) INTO v_patient_count 
    FROM patients 
    WHERE patient_id = p_patient_id;

    IF v_patient_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'Patient does not exist');
    END IF;

    -- Check if room exists
    SELECT COUNT(*) INTO v_room_count 
    FROM service_rooms 
    WHERE room_id = p_room_id;

    IF v_room_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20007, 'Room does not exist');
    END IF;

    -- Get next position in queue for this room
    SELECT NVL(MAX(queue_position), 0) + 1 INTO v_next_position
    FROM patient_queue
    WHERE room_id = p_room_id;

    -- Insert into queue
    INSERT INTO patient_queue (queue_id, patient_id, room_id, queue_position, status)
    VALUES (queue_seq.NEXTVAL, p_patient_id, p_room_id, v_next_position, 'waiting')
    RETURNING queue_id INTO p_queue_id;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Patient added to queue. ID: ' || p_queue_id || ', Position: ' || v_next_position);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_to_queue_proc;


-- Procedure to create a service request

create or replace PROCEDURE create_service_request_proc(
    p_patient_id IN NUMBER,
    p_room_id IN NUMBER,
    p_service_type IN VARCHAR2,
    p_priority IN VARCHAR2 DEFAULT 'medium',
    p_service_id OUT NUMBER
)
IS
    v_patient_count NUMBER;
    v_room_count NUMBER;
BEGIN
    -- Check if patient exists
    SELECT COUNT(*) INTO v_patient_count 
    FROM patients 
    WHERE patient_id = p_patient_id;

    IF v_patient_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Patient does not exist');
    END IF;

    -- Check if room exists
    SELECT COUNT(*) INTO v_room_count 
    FROM service_rooms 
    WHERE room_id = p_room_id;

    IF v_room_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Room does not exist');
    END IF;

    -- Validate priority
    IF p_priority NOT IN ('low', 'medium', 'high') THEN
        RAISE_APPLICATION_ERROR(-20005, 'Priority must be low, medium, or high');
    END IF;

    -- Insert service request
    INSERT INTO service_requests (service_id, patient_id, room_id, service_type, priority)
    VALUES (service_request_seq.NEXTVAL, p_patient_id, p_room_id, p_service_type, p_priority)
    RETURNING service_id INTO p_service_id;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Service request created. ID: ' || p_service_id);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END create_service_request_proc;


-- Procedure to generate a daily report 

create or replace PROCEDURE generate_daily_report_proc(
    p_date IN DATE DEFAULT TRUNC(SYSDATE)
)
IS
    v_total_patients NUMBER;
    v_completed NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== DAILY REPORT for ' || TO_CHAR(p_date, 'DD-MON-YYYY') || ' ===');
    DBMS_OUTPUT.PUT_LINE('');

    -- Count total patients
    SELECT COUNT(DISTINCT patient_id) INTO v_total_patients
    FROM patient_queue
    WHERE TRUNC(time_entered_queue) = p_date;

    -- Count completed
    SELECT COUNT(*) INTO v_completed
    FROM patient_queue
    WHERE TRUNC(time_entered_queue) = p_date
    AND status = 'completed';

    DBMS_OUTPUT.PUT_LINE('Total Patients: ' || v_total_patients);
    DBMS_OUTPUT.PUT_LINE('Completed: ' || v_completed);

    -- Room breakdown
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Room Breakdown:');
    DBMS_OUTPUT.PUT_LINE('---------------');

    FOR rec IN (
        SELECT sr.room_name, COUNT(pq.queue_id) as patient_count
        FROM patient_queue pq
        JOIN service_rooms sr ON pq.room_id = sr.room_id
        WHERE TRUNC(pq.time_entered_queue) = p_date
        GROUP BY sr.room_name
        ORDER BY patient_count DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(rec.room_name || ': ' || rec.patient_count || ' patients');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Report generated successfully.');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error generating report: ' || SQLERRM);
END generate_daily_report_proc;


-- Procedure to update the queue status for the patients

create or replace PROCEDURE update_queue_status_proc(
    p_queue_id IN NUMBER,
    p_new_status IN VARCHAR2,
    p_staff_id IN NUMBER DEFAULT NULL
)
IS
    v_current_status VARCHAR2(20);
BEGIN
    -- Get current status
    BEGIN
        SELECT status INTO v_current_status
        FROM patient_queue
        WHERE queue_id = p_queue_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20008, 'Queue ID not found');
    END;

    -- Validate new status
    IF p_new_status NOT IN ('waiting', 'in-progress', 'completed', 'skipped') THEN
        RAISE_APPLICATION_ERROR(-20009, 'Invalid status');
    END IF;

    -- Update status
    IF p_new_status = 'in-progress' THEN
        UPDATE patient_queue
        SET status = p_new_status,
            check_in_time = SYSTIMESTAMP
        WHERE queue_id = p_queue_id;
    ELSIF p_new_status = 'completed' THEN
        UPDATE patient_queue
        SET status = p_new_status,
            check_out_time = SYSTIMESTAMP
        WHERE queue_id = p_queue_id;
    ELSE
        UPDATE patient_queue
        SET status = p_new_status
        WHERE queue_id = p_queue_id;
    END IF;

    -- Log movement if staff_id provided
    IF p_staff_id IS NOT NULL THEN
        DECLARE
            v_patient_id NUMBER;
            v_room_id NUMBER;
        BEGIN
            SELECT patient_id, room_id INTO v_patient_id, v_room_id
            FROM patient_queue
            WHERE queue_id = p_queue_id;

            INSERT INTO movement_log (move_id, patient_id, room_id, move_time, action, queue_id, staff_id)
            VALUES (move_seq.NEXTVAL, v_patient_id, v_room_id, SYSTIMESTAMP, 
                   CASE p_new_status 
                       WHEN 'in-progress' THEN 'entered'
                       WHEN 'completed' THEN 'exited'
                       ELSE 'redirected'
                   END, 
                   p_queue_id, p_staff_id);
        END;
    END IF;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Queue status updated: ' || v_current_status || ' -> ' || p_new_status);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END update_queue_status_proc;

