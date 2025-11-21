-- DROP FUNCTION public.fn_validate_solution_creation(int8, int8, text, int8);

CREATE OR REPLACE FUNCTION public.fn_validate_solution_creation(p_immediate_parent_id bigint, p_root_parent_id bigint, p_child_module text, p_ref_requests_record_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_parent            public.requests%ROWTYPE;
    v_child_request     public.requests%ROWTYPE;
    v_config            jsonb;
    v_child_allowed     boolean := false;
    v_real_root         bigint;
    v_existing_link     RECORD;

    v_parent_sku        bigint;
    v_child_sku         bigint;
    v_parent_all_sku    boolean := false;

    rec RECORD;
BEGIN
    ----------------------------------------------------------------------
    -- 1. Validate immediate parent exists
    ----------------------------------------------------------------------
    SELECT * INTO v_parent
    FROM public.requests
    WHERE in_record_id = p_immediate_parent_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid immediate_parent=%', p_immediate_parent_id;
    END IF;

    ----------------------------------------------------------------------
    -- 2. Validate child request exists
    ----------------------------------------------------------------------
    SELECT * INTO v_child_request
    FROM public.requests
    WHERE in_record_id = p_ref_requests_record_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid child request=%', p_ref_requests_record_id;
    END IF;

    IF p_ref_requests_record_id = p_immediate_parent_id THEN
        RAISE EXCEPTION 'Child cannot equal parent';
    END IF;

    ----------------------------------------------------------------------
    -- 3. Load actionable configuration
    ----------------------------------------------------------------------
    SELECT actionable_config INTO v_config
    FROM public.actionables_execution_metadata
    ORDER BY in_record_id DESC LIMIT 1;

    IF v_config IS NULL THEN
        RAISE EXCEPTION 'Missing actionable_config.';
    END IF;

    ----------------------------------------------------------------------
    -- 4. Validate allowed child module
    ----------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(
            v_config #> ARRAY['module', v_parent.module, 'child_modules']
        ) AS t(val)
        WHERE lower(trim(val)) = lower(trim(p_child_module))
    ) THEN
        RAISE EXCEPTION
            'Child module % not allowed under %', p_child_module, v_parent.module;
    END IF;

    ----------------------------------------------------------------------
    -- 5. Calculate true root ancestor
    ----------------------------------------------------------------------
    WITH RECURSIVE up_tree AS (
        SELECT p_immediate_parent_id AS req_id, 0 AS depth
        UNION ALL
        SELECT rs.immediate_parent, depth + 1
        FROM up_tree ut
        JOIN public.requests_services rs
            ON rs.ref_requests_record_id = ut.req_id
    )
    SELECT req_id INTO v_real_root
    FROM up_tree ORDER BY depth DESC LIMIT 1;

    IF v_real_root IS NULL THEN
        v_real_root := p_immediate_parent_id;
    END IF;

    ----------------------------------------------------------------------
    -- 6. Check root parent matches expected
    ----------------------------------------------------------------------
    IF p_root_parent_id IS DISTINCT FROM v_real_root THEN
        RAISE EXCEPTION
            'Invalid root_parent %. Expected %', p_root_parent_id, v_real_root;
    END IF;

    ----------------------------------------------------------------------
    -- 7. Validate module matches
    ----------------------------------------------------------------------
    IF lower(trim(v_child_request.module)) <> lower(trim(p_child_module)) THEN
        RAISE EXCEPTION
            'Child module mismatch. expected %, got %',
            p_child_module, v_child_request.module;
    END IF;

    ----------------------------------------------------------------------
    -- 8. Skip SKU validation entirely when parent module IS NOT "Services"
    ----------------------------------------------------------------------
    IF lower(trim(v_parent.module)) <> 'services' THEN
        RETURN;
    END IF;

    ----------------------------------------------------------------------
    -- 9. Load SKU values (parent and child)
    ----------------------------------------------------------------------
    SELECT ref_services_sku INTO v_parent_sku
    FROM public.requests_services
    WHERE ref_requests_record_id = p_immediate_parent_id
    LIMIT 1;

    SELECT ref_services_sku INTO v_child_sku
    FROM public.requests_services
    WHERE ref_requests_record_id = p_ref_requests_record_id
    LIMIT 1;

    ----------------------------------------------------------------------
    -- 10. Skip SKU validation if either side has no SKU
    ----------------------------------------------------------------------
    IF v_parent_sku IS NULL OR v_child_sku IS NULL THEN
        RETURN;
    END IF;

    ----------------------------------------------------------------------
    -- 11. Enforce SKU dependency rule
    ----------------------------------------------------------------------
    SELECT COALESCE(all_sku, FALSE) INTO v_parent_all_sku
    FROM public.services_sku
    WHERE in_record_id = v_parent_sku;

    IF v_parent_all_sku = FALSE THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.services_sku_dependency
            WHERE ref_services_sku_parent = v_parent_sku
              AND ref_services_sku_child  = v_child_sku
        ) THEN
            RAISE EXCEPTION
                'SKU Dependency Error: parent SKU % does NOT allow child SKU %',
                v_parent_sku, v_child_sku;
        END IF;
    END IF;

    RETURN;
END;
$function$
;
