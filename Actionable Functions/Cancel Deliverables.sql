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
    v_sg_count INTEGER;
    v_msg TEXT;
BEGIN
    -- Validate allowed table names
    IF p_table_name NOT IN ('requests_delivery', 'requests_people', 'requests_problem') THEN
        RAISE EXCEPTION 'Table "%" is not allowed for deliverable cancellation.', p_table_name;
    END IF;

    -- Validate reduction amount
    IF p_reduce_by IS NULL OR p_reduce_by < 1 THEN
        RAISE EXCEPTION 'Reduction amount (p_reduce_by) must be at least 1.';
    END IF;

    -- Get current quantity directly (avoiding dynamic SQL for SELECT)
    EXECUTE format(
        'SELECT quantity FROM %I WHERE requests = $1 AND master_key = $2',
        p_table_name
    ) INTO v_current_quantity USING p_requests, p_master_key;

    IF v_current_quantity IS NULL THEN
        RETURN format('No matching record found in table "%s" for requests = "%s" and master_key = "%s".',
                      p_table_name, p_requests, p_master_key);
    END IF;

    -- Calculate new quantity
    v_new_quantity := v_current_quantity - p_reduce_by;

    -- Ensure new quantity is at least 1
    IF v_new_quantity < 1 THEN
        RETURN format('Cannot reduce quantity below 1. Current quantity: %s, attempted reduction: %s.',
                      v_current_quantity, p_reduce_by);
    END IF;

    -- Special logic for requests_delivery with SG values
    IF p_table_name = 'requests_delivery' AND p_sg_values IS NOT NULL THEN
        v_sg_count := array_length(string_to_array(p_sg_values, ','), 1);

        IF v_sg_count IS NULL OR v_sg_count < 1 THEN
            RETURN 'SG values must contain at least one SG.';
        END IF;

        -- Update SG_values and quantity
        EXECUTE format(
            'UPDATE %I SET sg_values = $1, quantity = $2 WHERE requests = $3 AND master_key = $4',
            p_table_name
        ) USING p_sg_values, v_sg_count, p_requests, p_master_key;

        RETURN format('SG values updated and quantity set to %s in %s (SG count: %s).', v_sg_count, p_table_name, v_sg_count);
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
    p_reduce_by       := 10
);

