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
    'request_delivery2',
    'PS-2025-019',
    NULL,
    '3'
);
