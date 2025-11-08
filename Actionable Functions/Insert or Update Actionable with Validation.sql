CREATE OR REPLACE FUNCTION public.fn_validate_all_actionables_insert_or_update()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_json jsonb;
    v_module text;
    v_req_status text;
    v_req_stage text;
    v_valid boolean := false;
    v_request_id bigint;
    v_existing record;
    v_next_stage_list jsonb;
    v_new_status text;
    v_new_stage text;
BEGIN
    -- Set created_by and creation_time on insert
    IF TG_OP = 'INSERT' THEN
        NEW.created_by := COALESCE(NEW.created_by, current_user::text);
        NEW.actionable_creation_time := COALESCE(NEW.actionable_creation_time, now());
    END IF;

    -- Get parent request details
    SELECT r.master_id, r.module, r.status, r.stage
    INTO v_request_id, v_module, v_req_status, v_req_stage
    FROM public.requests r
    WHERE r.master_id = NEW.request_subject
    LIMIT 1;

    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'No matching request found for actionable "%".', NEW.request_subject;
    END IF;

    -- Load latest JSON configuration
    SELECT json_actionable_data
    INTO v_json
    FROM public.json_actionable
    ORDER BY master_id DESC
    LIMIT 1;

    IF v_json IS NULL THEN
        RAISE EXCEPTION 'JSON configuration missing in json_actionable.';
    END IF;

    -- Validate actionable against current status and stage
    v_valid := EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_json -> 'module' -> v_module -> 'actionables') elem
        WHERE elem ->> 'Actionable Name' = NEW.actionable_name
          AND (
              elem -> 'solution_status' -> v_req_status ? v_req_stage
              OR elem -> 'solution_status' -> v_req_status IS NOT NULL
          )
    );

    IF NOT v_valid THEN
        RAISE EXCEPTION 'Actionable "%" is not valid for module "%" at status "%" / "%".',
            NEW.actionable_name, v_module, v_req_status, v_req_stage;
    END IF;

    -- Handle insert logic
    IF TG_OP = 'INSERT' THEN
        SELECT a.*
        INTO v_existing
        FROM public.all_actionables a
        WHERE a.request_subject = NEW.request_subject
          AND lower(a.actionable_name) = lower(NEW.actionable_name)
          AND a.actionable_status = 'Complete'
        LIMIT 1;

        IF FOUND THEN
            RAISE EXCEPTION 'Actionable "%" already completed by "%". Insert not allowed.',
                NEW.actionable_name, COALESCE(v_existing.completed_by, 'unknown');
        END IF;

        NEW.actionable_status := CASE
            WHEN NEW.completed_by IS NULL OR trim(NEW.completed_by) = ''
              OR NEW.actionable_completion_time IS NULL THEN 'Open'
            ELSE 'Complete'
        END;

        RETURN NEW;
    END IF;

    -- Handle update logic
    IF TG_OP = 'UPDATE' THEN
        IF lower(NEW.actionable_status) = 'complete'
           AND OLD.actionable_status IS DISTINCT FROM NEW.actionable_status THEN

            -- Revalidate before completing
            IF NOT v_valid THEN
                RAISE EXCEPTION 'Cannot complete actionable "%" for module "%" due to invalid state "%" / "%".',
                    NEW.actionable_name, v_module, v_req_status, v_req_stage;
            END IF;

            -- Check mandatory fields before completion
            IF NEW.estimated_completion_time IS NULL THEN
                RAISE EXCEPTION 'estimated_on_hold_date must be filled before completing actionable "%".',
                    NEW.actionable_name;
            END IF;

            IF lower(NEW.stage) = 'others'
               AND (NEW.reason_for_hold IS NULL OR trim(NEW.reason_for_hold) = '') THEN
                RAISE EXCEPTION 'reason_for_hold is mandatory when stage = "Others".';
            END IF;

            -- Fill completion details
            NEW.completed_by := COALESCE(NULLIF(trim(NEW.completed_by), ''), current_user::text);
            NEW.actionable_completion_time := COALESCE(NEW.actionable_completion_time, now());

            -- Determine next status and stage from JSON
            v_next_stage_list := v_json -> 'module' -> v_module -> 'solution_status'
                                 -> v_req_status -> v_req_stage -> 'next_status_stage';

            -- Apply auto-transition logic for specific actionables
            IF lower(NEW.actionable_name) IN ('hold request', 'restart request', 'close request') THEN
                CASE lower(NEW.actionable_name)
                    WHEN 'hold request' THEN
                        v_new_status := 'On Hold';
                        v_new_stage := COALESCE(NEW.stage, 'Customer Response Awaited');
                    WHEN 'restart request' THEN
                        v_new_status := 'Open';
                        v_new_stage := 'Active';
                    WHEN 'close request' THEN
                        v_new_status := 'Close';
                        v_new_stage := 'Resolved';
                END CASE;

                -- Update parent request with new status and stage
                UPDATE public.requests
                SET status = v_new_status,
                    stage = v_new_stage,
                    estimated_on_hold_date = NEW.estimated_completion_time,
                    reason_for_hold = CASE WHEN lower(v_new_stage) = 'others' THEN NEW.reason_for_hold ELSE reason_for_hold END,
                    modified_time = now()
                WHERE master_id = v_request_id;

                RAISE NOTICE 'Request % updated to % / % after actionable "%".',
                    v_request_id, v_new_status, v_new_stage, NEW.actionable_name;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
