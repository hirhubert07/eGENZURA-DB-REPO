-- Create compound trigger for STAFF_USERS table
CREATE OR REPLACE TRIGGER trg_restrict_staff_changes
FOR INSERT OR UPDATE OR DELETE ON staff_users
COMPOUND TRIGGER

    -- Type declarations
    TYPE t_audit_rec IS RECORD (
        table_name VARCHAR2(50),
        operation_type VARCHAR2(10),
        employee_id NUMBER,
        staff_id NUMBER,
        restriction_applied CHAR(1),
        error_message VARCHAR2(500)
    );
    
    TYPE t_audit_table IS TABLE OF t_audit_rec;
    v_audit_data t_audit_table := t_audit_table();
    
    -- Before statement section
    BEFORE STATEMENT IS
    BEGIN
        v_audit_data.DELETE; -- Clear collection for new statement
    END BEFORE STATEMENT;
    
    -- Before each row section
    BEFORE EACH ROW IS
        v_restricted BOOLEAN;
    BEGIN
        -- Check restriction
        v_restricted := is_restricted_day();
        
        IF v_restricted THEN
            -- Add to audit collection
            v_audit_data.EXTEND;
            v_audit_data(v_audit_data.LAST).table_name := 'STAFF_USERS';
            v_audit_data(v_audit_data.LAST).operation_type := 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END;
            v_audit_data(v_audit_data.LAST).employee_id := :NEW.staff_id;
            v_audit_data(v_audit_data.LAST).staff_id := :NEW.staff_id;
            v_audit_data(v_audit_data.LAST).restriction_applied := 'Y';
            v_audit_data(v_audit_data.LAST).error_message := 
                'Staff user modifications restricted on weekdays/holidays';
            
            -- Raise error immediately
            RAISE_APPLICATION_ERROR(-20904, 
                'Staff user operations not permitted on weekdays or holidays. ' ||
                'Operation: ' || v_audit_data(v_audit_data.LAST).operation_type || ' ' ||
                'Staff ID: ' || v_audit_data(v_audit_data.LAST).staff_id
            );
        ELSE
            -- Add allowed operation to collection
            v_audit_data.EXTEND;
            v_audit_data(v_audit_data.LAST).table_name := 'STAFF_USERS';
            v_audit_data(v_audit_data.LAST).operation_type := 
                CASE 
                    WHEN INSERTING THEN 'INSERT'
                    WHEN UPDATING THEN 'UPDATE'
                    WHEN DELETING THEN 'DELETE'
                END;
            v_audit_data(v_audit_data.LAST).employee_id := :NEW.staff_id;
            v_audit_data(v_audit_data.LAST).staff_id := :NEW.staff_id;
            v_audit_data(v_audit_data.LAST).restriction_applied := 'N';
            v_audit_data(v_audit_data.LAST).error_message := NULL;
        END IF;
    END BEFORE EACH ROW;
    
    -- After statement section (for logging allowed operations)
    AFTER STATEMENT IS
        v_audit_id NUMBER;
    BEGIN
        -- Log all non-restricted operations
        FOR i IN 1..v_audit_data.COUNT LOOP
            IF v_audit_data(i).restriction_applied = 'N' THEN
                v_audit_id := log_restriction_audit(
                    p_table_name => v_audit_data(i).table_name,
                    p_operation_type => v_audit_data(i).operation_type,
                    p_employee_id => v_audit_data(i).employee_id,
                    p_restriction_applied => v_audit_data(i).restriction_applied,
                    p_error_message => v_audit_data(i).error_message
                );
            END IF;
        END LOOP;
    END AFTER STATEMENT;
    
END trg_restrict_staff_changes;
/

-- Verify compound trigger is created
SELECT trigger_name, table_name, trigger_type, status 
FROM user_triggers 
WHERE trigger_name = 'TRG_RESTRICT_STAFF_CHANGES';