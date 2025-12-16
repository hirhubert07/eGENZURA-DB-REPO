-- Simple trigger for PATIENTS table
CREATE OR REPLACE TRIGGER trg_restrict_patient_changes
BEFORE INSERT OR UPDATE OR DELETE ON patients
FOR EACH ROW
DECLARE
    v_restricted BOOLEAN;
    v_employee_id NUMBER;
    v_audit_id NUMBER;
    v_error_message VARCHAR2(500);
BEGIN
    -- Simulate employee ID (in real system, this would come from session/application)
    -- Using patient_id as placeholder for employee_id in this demo
    v_employee_id := NVL(:NEW.patient_id, :OLD.patient_id);
    
    -- Check restriction
    v_restricted := is_restricted_day();
    
    IF v_restricted THEN
        -- Build error message
        v_error_message := 'Employee operations not permitted on ';
        
        IF TO_CHAR(SYSDATE, 'D') IN ('2','3','4','5','6') THEN
            v_error_message := v_error_message || 'weekdays';
        ELSE
            v_error_message := v_error_message || 'weekends';
        END IF;
        
        -- Check if holiday
        BEGIN
            SELECT 'Y' INTO v_error_message
            FROM system_holidays
            WHERE holiday_date = TRUNC(SYSDATE)
            AND ROWNUM = 1;
            
            v_error_message := 'Employee operations not permitted on public holidays';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
        
        -- Log the attempt
        v_audit_id := log_restriction_audit(
            p_table_name => 'PATIENTS',
            p_operation_type => 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END,
            p_employee_id => v_employee_id,
            p_restriction_applied => 'Y',
            p_error_message => v_error_message
        );
        
        -- Raise application error
        RAISE_APPLICATION_ERROR(-20901, 
            v_error_message || '. ' ||
            'Audit ID: ' || v_audit_id || '. ' ||
            'Date: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY')
        );
    ELSE
        -- Log allowed operation
        v_audit_id := log_restriction_audit(
            p_table_name => 'PATIENTS',
            p_operation_type => 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END,
            p_employee_id => v_employee_id,
            p_restriction_applied => 'N',
            p_error_message => NULL
        );
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Re-raise the exception
        RAISE;
END trg_restrict_patient_changes;
/

-- Simple trigger for SERVICE_REQUESTS table
CREATE OR REPLACE TRIGGER trg_restrict_service_changes
BEFORE INSERT OR UPDATE OR DELETE ON service_requests
FOR EACH ROW
DECLARE
    v_restricted BOOLEAN;
    v_employee_id NUMBER;
    v_audit_id NUMBER;
BEGIN
    -- Get employee ID (using patient_id as placeholder)
    v_employee_id := NVL(:NEW.patient_id, :OLD.patient_id);
    
    -- Check restriction
    v_restricted := is_restricted_day();
    
    IF v_restricted THEN
        -- Log the attempt
        v_audit_id := log_restriction_audit(
            p_table_name => 'SERVICE_REQUESTS',
            p_operation_type => 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END,
            p_employee_id => v_employee_id,
            p_restriction_applied => 'Y',
            p_error_message => 'Operation restricted on weekdays/holidays'
        );
        
        -- Raise error
        RAISE_APPLICATION_ERROR(-20902, 
            'Employee operations on SERVICE_REQUESTS not permitted on weekdays or holidays. ' ||
            'Audit ID: ' || v_audit_id
        );
    ELSE
        -- Log allowed operation
        v_audit_id := log_restriction_audit(
            p_table_name => 'SERVICE_REQUESTS',
            p_operation_type => 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END,
            p_employee_id => v_employee_id,
            p_restriction_applied => 'N',
            p_error_message => NULL
        );
    END IF;
    
END trg_restrict_service_changes;
/

-- Simple trigger for PATIENT_QUEUE table (with exception for status updates)
CREATE OR REPLACE TRIGGER trg_restrict_queue_changes
BEFORE INSERT OR UPDATE OR DELETE ON patient_queue
FOR EACH ROW
DECLARE
    v_restricted BOOLEAN;
    v_employee_id NUMBER;
    v_audit_id NUMBER;
BEGIN
    -- IMPORTANT EXCEPTION: Allow status updates even on restricted days
    -- This ensures patient flow isn't disrupted
    IF UPDATING AND :OLD.status IS NOT NULL AND :NEW.status IS NOT NULL THEN
        -- Allow status changes (like updating from 'waiting' to 'completed')
        RETURN;
    END IF;
    
    -- Get employee ID (using patient_id as placeholder)
    v_employee_id := NVL(:NEW.patient_id, :OLD.patient_id);
    
    -- Check restriction
    v_restricted := is_restricted_day();
    
    IF v_restricted THEN
        -- Log the attempt
        v_audit_id := log_restriction_audit(
            p_table_name => 'PATIENT_QUEUE',
            p_operation_type => 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END,
            p_employee_id => v_employee_id,
            p_restriction_applied => 'Y',
            p_error_message => 'Queue operations restricted on weekdays/holidays'
        );
        
        -- Raise error
        RAISE_APPLICATION_ERROR(-20903, 
            'Employee queue operations not permitted on weekdays or holidays. ' ||
            'Exception: Status updates are allowed. ' ||
            'Audit ID: ' || v_audit_id
        );
    ELSE
        -- Log allowed operation
        v_audit_id := log_restriction_audit(
            p_table_name => 'PATIENT_QUEUE',
            p_operation_type => 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END,
            p_employee_id => v_employee_id,
            p_restriction_applied => 'N',
            p_error_message => NULL
        );
    END IF;
    
END trg_restrict_queue_changes;
/

-- Verify triggers are created
SELECT trigger_name, table_name, trigger_type, status 
FROM user_triggers 
WHERE trigger_name LIKE 'TRG_RESTRICT_%'
ORDER BY trigger_name;