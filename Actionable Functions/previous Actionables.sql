CREATE OR REPLACE FUNCTION public.fn_update_description(
    p_table_name TEXT,
    p_requests TEXT,
    p_master_key TEXT,
    p_new_instructions TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    request_exists BOOLEAN;
    sql_check TEXT;
    sql_update TEXT;
BEGIN
    -- Validate allowed table names
    IF p_table_name NOT IN ('requests_problem', 'requests_people', 'requests_delivery') THEN
        RAISE EXCEPTION 'Table "%" is not allowed for updates.', p_table_name;
    END IF;

    -- Build dynamic SQL to check if the record exists
    sql_check := FORMAT(
        'SELECT EXISTS (SELECT 1 FROM %I WHERE requests = $1 AND master_key = $2)',
        p_table_name
    );
    EXECUTE sql_check INTO request_exists USING p_requests, p_master_key;

    IF NOT request_exists THEN
        RAISE EXCEPTION 'No matching record found in table "%" where requests = "%" and master_key = "%".',
            p_table_name, p_requests, p_master_key;
    END IF;

    -- Build dynamic SQL to perform the update
    sql_update := FORMAT(
        'UPDATE %I SET request_instructions = $1 WHERE requests = $2 AND master_key = $3',
        p_table_name
    );
    EXECUTE sql_update USING p_new_instructions, p_requests, p_master_key;

    RETURN FORMAT('Request updated successfully in table %s for master_key %s', p_table_name, p_master_key);
END;
$function$;







SELECT public.fn_update_description(
    'requests_problem',  -- fixed spelling
    'request1',
    'REQ-2025-001',
    'Please follow the updated protocol for data validation.'
);



SELECT requests, master_key
FROM requests_problem
WHERE master_key = 'REQ-2025-001';
----------------------------------------estimated_completion_date-------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_update_estimated_completion_date(
    p_table_name TEXT,
    p_requests TEXT,
    p_master_key TEXT,
    p_new_date DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    request_exists BOOLEAN;
    sql_check TEXT;
    sql_update TEXT;
    full_timestamp TIMESTAMP;
BEGIN
    -- Validate allowed table names
    IF p_table_name NOT IN ('requests_problem', 'requests_people', 'requests_delivery') THEN
        RAISE EXCEPTION 'Table "%" is not allowed for updates.', p_table_name;
    END IF;

    -- Convert date to timestamp with default time (00:00:00)
    full_timestamp := p_new_date::timestamp;

    -- Check if the record exists
    sql_check := FORMAT(
        'SELECT EXISTS (SELECT 1 FROM %I WHERE requests = $1 AND master_key = $2)',
        p_table_name
    );
    EXECUTE sql_check INTO request_exists USING p_requests, p_master_key;

    IF NOT request_exists THEN
        RAISE EXCEPTION 'No matching record found in table "%" where requests = "%" and master_key = "%".',
            p_table_name, p_requests, p_master_key;
    END IF;

    -- Perform the update
    sql_update := FORMAT(
        'UPDATE %I SET estimated_completion_date = $1 WHERE requests = $2 AND master_key = $3',
        p_table_name
    );
    EXECUTE sql_update USING full_timestamp, p_requests, p_master_key;

    RETURN FORMAT('Estimated completion date updated in table %s for master_key %s', p_table_name, p_master_key);
END;
$function$;




SELECT public.fn_update_estimated_completion_date(
    'requests_problem',
    'request1',
    'REQ-2025-001',
    '2025-12-15'
);

----------------------------------------------update_sg/qunatity-------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_update_quantity_or_sg_values(
    p_table_name TEXT,
    p_requests TEXT,
    p_master_key TEXT,
    p_sg_values TEXT,
    p_quantity INTEGER
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    request_exists BOOLEAN;
    sql_check TEXT;
    sql_update TEXT;
    sg_count INTEGER;
BEGIN
    -- Validate allowed table names
    IF p_table_name NOT IN ('requests_problem', 'requests_people', 'requests_delivery') THEN
        RAISE EXCEPTION 'Table "%" is not allowed for updates.', p_table_name;
    END IF;

    -- Check if the record exists
    sql_check := FORMAT(
        'SELECT EXISTS (SELECT 1 FROM %I WHERE requests = $1 AND master_key = $2)',
        p_table_name
    );
    EXECUTE sql_check INTO request_exists USING p_requests, p_master_key;

    IF NOT request_exists THEN
        RAISE EXCEPTION 'No matching record found in table "%" where requests = "%" and master_key = "%".',
            p_table_name, p_requests, p_master_key;
    END IF;

    -- Special logic for requests_delivery
    IF p_table_name = 'requests_delivery' THEN
        IF p_sg_values IS NOT NULL THEN
            -- Count SGs by splitting comma-separated values
            sg_count := array_length(string_to_array(p_sg_values, ','), 1);

            -- Update SG_values and quantity
            sql_update := FORMAT(
                'UPDATE %I SET SG_values = $1, quantity = $2 WHERE requests = $3 AND master_key = $4',
                p_table_name
            );
            EXECUTE sql_update USING p_sg_values, sg_count, p_requests, p_master_key;

            RETURN FORMAT('SG_values and quantity updated in %s (SG count: %s)', p_table_name, sg_count);
        ELSE
            -- Only update quantity
            sql_update := FORMAT(
                'UPDATE %I SET quantity = $1 WHERE requests = $2 AND master_key = $3',
                p_table_name
            );
            EXECUTE sql_update USING p_quantity, p_requests, p_master_key;

            RETURN FORMAT('Quantity updated in %s to %s', p_table_name, p_quantity);
        END IF;
    ELSE
        -- For other tables, just update quantity
        sql_update := FORMAT(
            'UPDATE %I SET quantity = $1 WHERE requests = $2 AND master_key = $3',
            p_table_name
        );
        EXECUTE sql_update USING p_quantity, p_requests, p_master_key;

        RETURN FORMAT('Quantity updated in %s to %s', p_table_name, p_quantity);
    END IF;
END;
$function$;

SELECT public.fn_update_quantity_or_sg_values(
    'requests_delivery',
    'delivery 5',
    'REQ-2025-005',
    'SG1,SG2,SG3,SG4,SG5',
    null
);




--------------------------------------------- change Owner-------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ac_change_request_owner(
    request_table TEXT,
    p_requests TEXT,
    p_master_key TEXT,
    new_owner TEXT
) RETURNS VOID AS $$
BEGIN
    -- Check if new_owner exists in users table
    IF NOT EXISTS (SELECT 1 FROM "users" WHERE "master_key" = new_owner) THEN
        RAISE EXCEPTION 'New owner "%" does not exist in users table', new_owner;
    END IF;

    -- Update the owner in the specified request table
    IF request_table = 'requests_problem' THEN
        UPDATE "requests_problem"
        SET "owner" = new_owner
        WHERE "requests" = p_requests AND "master_key" = p_master_key
          AND EXISTS (
              SELECT 1 FROM "users"
              WHERE "master_key" = "requests_problem"."owner"
          );
    ELSIF request_table = 'requests_delivery' THEN
        UPDATE "requests_delivery"
        SET "owner" = new_owner
        WHERE "requests" = p_requests AND "master_key" = p_master_key
          AND EXISTS (
              SELECT 1 FROM "users"
              WHERE "master_key" = "requests_delivery"."owner"
          );
    ELSIF request_table = 'requests_people' THEN
        UPDATE "requests_people"
        SET "owner" = new_owner
        WHERE "requests" = p_requests AND "master_key" = p_master_key
          AND EXISTS (
              SELECT 1 FROM "users"
              WHERE "master_key" = "requests_people"."owner"
          );
    ELSE
        RAISE EXCEPTION 'Invalid request table name "%" provided', request_table;
    END IF;
END;
$$ LANGUAGE plpgsql;


SELECT fn_ac_change_request_owner(
    'requests_problem',
    'Problem 8',
    'REQ-2025-008',
    'users_internaludit'
);




SELECT public.fn_ac_change_request_owner(
    'requests_problem'::text,
    789456::bigint,         -- Replace 12345 with the actual ticket_id
    'users_internalayush'::text          -- Replace 'ayush' with the new owner's master_key
);

update requests_problem 
set owner = 'users_internaludit'
where request_subject = 'raising a test Problem8';

SELECT public.fn_ac_change_request_owner(
    'requests_delivery',
    'delivery 1',
    'REQ-2025-001',
    'udit',
    'ayush'
);

-------------------------------------------------cancel Deliverables--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ac_cancel_deliverable(
    p_table_name TEXT,
    p_requests VARCHAR,
    p_master_key VARCHAR,
    p_reduce_by INTEGER,
    p_sg_values TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_quantity INTEGER;
    v_new_quantity INTEGER;
    v_existing_sgs TEXT;
    v_updated_sgs TEXT;
    v_sg_array TEXT[];
    v_remove_array TEXT[];
    v_filtered_array TEXT[];
BEGIN
    -- Validate allowed table names
    IF p_table_name NOT IN ('requests_delivery', 'requests_people', 'requests_problem') THEN
        RAISE EXCEPTION 'Table "%" is not allowed for deliverable cancellation.', p_table_name;
    END IF;

    -- Validate reduction amount
    IF p_reduce_by IS NULL OR p_reduce_by < 1 THEN
        RAISE EXCEPTION 'Reduction amount (p_reduce_by) must be at least 1.';
    END IF;

    -- Get current quantity and SG values
    EXECUTE format(
        'SELECT quantity, sg_values FROM %I WHERE requests = $1 AND master_key = $2',
        p_table_name
    ) INTO v_current_quantity, v_existing_sgs USING p_requests, p_master_key;

    IF v_current_quantity IS NULL THEN
        RETURN format('No matching record found in table "%s" for requests = "%s" and master_key = "%s".',
                      p_table_name, p_requests, p_master_key);
    END IF;

    -- Calculate new quantity
    v_new_quantity := v_current_quantity - p_reduce_by;

    IF v_new_quantity < 1 THEN
        RETURN format('Cannot reduce quantity below 1. Current quantity: %s, attempted reduction: %s.',
                      v_current_quantity, p_reduce_by);
    END IF;

    -- If SG values are provided, remove them from existing SG list
    IF p_table_name = 'requests_delivery' AND p_sg_values IS NOT NULL THEN
        v_sg_array := string_to_array(v_existing_sgs, ',');
        v_remove_array := string_to_array(p_sg_values, ',');

        -- Filter out SGs to be removed
        v_filtered_array := ARRAY(
            SELECT unnest(v_sg_array)
            EXCEPT
            SELECT unnest(v_remove_array)
        );

        -- Convert back to comma-separated string
        v_updated_sgs := array_to_string(v_filtered_array, ',');

        -- Update SG_values and quantity
        EXECUTE format(
            'UPDATE %I SET sg_values = $1, quantity = $2 WHERE requests = $3 AND master_key = $4',
            p_table_name
        ) USING v_updated_sgs, v_new_quantity, p_requests, p_master_key;

        RETURN format('Removed SGs [%s]. Updated SG_values: "%s", quantity: %s in %s.',
                      p_sg_values, v_updated_sgs, v_new_quantity, p_table_name);
    ELSE
        -- Update only quantity
        EXECUTE format(
            'UPDATE %I SET quantity = $1 WHERE requests = $2 AND master_key = $3',
            p_table_name
        ) USING v_new_quantity, p_requests, p_master_key;

        RETURN format('Quantity updated in %s from %s to %s.', p_table_name, v_current_quantity, v_new_quantity);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RETURN format('Error: %s', SQLERRM);
END;
$function$;



SELECT public.fn_ac_cancel_deliverable(
    p_table_name      := 'requests_delivery',
    p_requests        := 'delivery 5',
    p_master_key      := 'REQ-2025-005',
    p_sg_values       := 'SG5',
    p_reduce_by       := 1
);





-------------------------------------------------Create Solution_---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ac_create_child_solution(
    p_parent_table TEXT,
    p_parent_requests TEXT,
    p_parent_master_key TEXT,
    p_child_table TEXT,
    p_table_api TEXT,
    p_child_requests TEXT,
    p_child_master_key TEXT,
    p_owner TEXT,
    p_status TEXT,
    p_stage TEXT,
    p_request_subject TEXT,
    p_quantity INTEGER DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_exists BOOLEAN;
BEGIN
    -- Validate parent and child table names
    IF p_parent_table NOT IN ('requests_problem', 'requests_delivery') THEN
        RAISE EXCEPTION 'Invalid parent table: "%". Allowed: requests_problem, requests_delivery.', p_parent_table;
    END IF;

    IF p_child_table NOT IN ('requests_delivery', 'requests_people') THEN
        RAISE EXCEPTION 'Invalid child table: "%". Allowed: requests_delivery, requests_people.', p_child_table;
    END IF;

    -- Check if parent request exists
    EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM %I WHERE requests = $1 AND master_key = $2)',
        p_parent_table
    ) INTO parent_exists USING p_parent_requests, p_parent_master_key;

    IF NOT parent_exists THEN
        RETURN format('No parent request found in "%s" for requests = "%s" and master_key = "%s".',
                      p_parent_table, p_parent_requests, p_parent_master_key);
    END IF;

    -- If inserting into requests_delivery, quantity is required
    IF p_child_table = 'requests_delivery' THEN
        IF p_quantity IS NULL OR p_quantity < 1 THEN
            RAISE EXCEPTION 'Quantity must be provided and greater than 0 when inserting into requests_delivery.';
        END IF;

        EXECUTE format(
            'INSERT INTO %I (requests, master_key, owner, status, stage, table_api, parent_id, request_subject, quantity)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
            p_child_table
        ) USING p_child_requests, p_child_master_key, p_owner, p_status, p_stage, p_table_api, p_parent_master_key, p_request_subject, p_quantity;
    ELSE
        -- For requests_people (or others), no quantity needed
        EXECUTE format(
            'INSERT INTO %I (requests, master_key, owner, status, stage, table_api, parent_id, request_subject)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
            p_child_table
        ) USING p_child_requests, p_child_master_key, p_owner, p_status, p_stage, p_table_api, p_parent_master_key, p_request_subject;
    END IF;

    RETURN format('Child solution "%s" created in "%s" under parent "%s".',
                  p_child_requests, p_child_table, p_parent_master_key);
END;
$function$;





SELECT public.fn_ac_create_child_solution(
    'requests_problem',         -- Parent table
    'Problem 8',                -- Parent request
    'REQ-2025-008',             -- Parent master key
    'requests_delivery',        -- Child table
    'requests_delivery',        -- Table API
    'solution 4',               -- Child request
    'REQ-2025-014',             -- Child master key
    'user_internalayush',       -- Owner
    'Assigned',                 -- Status
    'Service Lead Assigned',    -- Stage
    'raising demo child solution', -- Request subject
     6                       -- Quantity
);


-----------------------------------------------cancel requests-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ac_cancel_request(
    p_table_name TEXT,
    p_requests TEXT,
    p_master_key TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_request_exists BOOLEAN;
    v_has_sgs BOOLEAN;
BEGIN
    --  Validate allowed tables
    IF p_table_name NOT IN ('requests_delivery', 'requests_people') THEN
        RAISE EXCEPTION 'Table "%" is not allowed for cancellation.', p_table_name;
    END IF;

    -------------------------------------------------------------------------
    -- 1️⃣ Check if the record exists
    -------------------------------------------------------------------------
    EXECUTE format(
        'SELECT EXISTS (
            SELECT 1
            FROM %I
            WHERE requests = $1 AND master_key = $2
        )',
        p_table_name
    )
    INTO v_request_exists
    USING p_requests, p_master_key;

    IF NOT v_request_exists THEN
        RETURN format(
            'No matching record found in "%s" for requests = "%s" and master_key = "%s".',
            p_table_name, p_requests, p_master_key
        );
    END IF;

    -------------------------------------------------------------------------
    -- 2️⃣ Check if SG values exist and are not empty
    -------------------------------------------------------------------------
    EXECUTE format(
        'SELECT COALESCE(sg_values <> '''' AND sg_values IS NOT NULL, FALSE)
         FROM %I
         WHERE requests = $1 AND master_key = $2',
        p_table_name
    )
    INTO v_has_sgs
    USING p_requests, p_master_key;

    -------------------------------------------------------------------------
    -- Perform the update based on SG presence
    -------------------------------------------------------------------------
    IF v_has_sgs THEN
        EXECUTE format(
            'UPDATE %I
             SET sg_values = '''',
                 quantity = 0,
                 status = ''Closed'',
                 stage = ''Cancelled''
             WHERE requests = $1 AND master_key = $2',
            p_table_name
        )
        USING p_requests, p_master_key;

        RETURN format(
            'Request "%s" cancelled in table "%s". SG values cleared, quantity set to 0, status Closed, stage Cancelled.',
            p_requests, p_table_name
        );
    ELSE
        EXECUTE format(
            'UPDATE %I
             SET quantity = 0,
                 status = ''Closed'',
                 stage = ''Cancelled''
             WHERE requests = $1 AND master_key = $2',
            p_table_name
        )
        USING p_requests, p_master_key;

        RETURN format(
            'Request "%s" cancelled in table "%s". Quantity set to 0, status Closed, stage Cancelled.',
            p_requests, p_table_name
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN format('Error in fn_ac_cancel_request: %s', SQLERRM);
END;
$function$;



SELECT public.fn_ac_cancel_request(
    p_table_name := 'requests_delivery',
    p_requests := 'solution 4',
    p_master_key := 'REQ-2025-014'
);


------------------------------------------------------Create Task------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ac_create_task(
    p_source_table TEXT,
    p_requests TEXT,
    p_master_key TEXT,
    p_task_title TEXT,
    p_task_description TEXT,
    p_assigned_to TEXT,
    p_due_date DATE DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    source_exists BOOLEAN;
BEGIN
    -- Validate source table
    IF p_source_table NOT IN ('requests_problem', 'requests_delivery', 'requests_people') THEN
        RAISE EXCEPTION 'Invalid source table: "%". Allowed: requests_problem, requests_delivery, requests_people.', p_source_table;
    END IF;

    -- Check if source record exists
    EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM %I WHERE requests = $1 AND master_key = $2)',
        p_source_table
    ) INTO source_exists USING p_requests, p_master_key;

    IF NOT source_exists THEN
        RETURN format('No matching source found in "%s" for requests = "%s" and master_key = "%s".',
                      p_source_table, p_requests, p_master_key);
    END IF;

    -- Simulate task creation (future DB integration placeholder)
    RETURN format(
        'Task "%s" created for request "%s" (master_key: %s) from table "%s". Assigned to: %s%s',
        p_task_title,
        p_requests,
        p_master_key,
        p_source_table,
        p_assigned_to,
        CASE WHEN p_due_date IS NOT NULL THEN format(', Due by: %s', p_due_date) ELSE '' END
    );
END;
$function$;


SELECT public.fn_ac_create_task(
    'requests_delivery',         -- Source table
    'solution 3',                -- Request name
    'REQ-2025-013',              -- Master key
    'Follow-up on server reboot',-- Task title
    'Ensure cache is monitored for next 7 days', -- Task description
    'user_internalayush',        -- Assigned to
    '2025-11-10'                 -- Due date
);


--------------------------------------------------------------------------------------------------------------------------------------




SELECT EXISTS (SELECT 1 FROM requests_delivery WHERE requests = 'solution 4' AND master_key = 'REQ-2025-014');



-------------------------------------------------------------------------------------------------------------------------------------
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE domain_name = 'checkbox';
-------------------------------------------------------------------------------------------------------------------------------------

truncate table requests_problem;
truncate table requests_delivery;
truncate table requests_people;

ALTER DOMAIN public.master_id DROP DEFAULT;
ALTER DOMAIN public.master_id DROP CONSTRAINT auto_number_check;






insert into requests_problem (table_api,requests,request_subject,request_instructions,quantity,master_key)
values('request_problem','request1','raising a test problem','raisng a test problem for testing purpose',1,'REQ-2025-001');

insert into requests_delivery (table_api,requests,request_subject,request_instructions,sg_values,quantity,master_key)
values('request_delivery','request_delivery1','raising a test delivery','raisng a test deliveryfor testing purpose','sg1',1,'PS-2025-018');

insert into requests_delivery (table_api,requests,request_subject,request_instructions,quantity,master_key)
values('request_delivery','request_delivery2','raising a test delivery','raisng a test deliveryfor testing purpose',1,'PS-2025-019');


ALTER DOMAIN public."_master_key1" DROP CONSTRAINT _master_key1_check;






