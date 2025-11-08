---------0) One-time DDL (if not done)
-- Ensure all_actionables.request_subject is a FK to requests(master_id)
ALTER TABLE public.all_actionables
  ALTER COLUMN request_subject TYPE bigint USING request_subject::bigint,
  ADD CONSTRAINT all_actionables_request_fk
    FOREIGN KEY (request_subject) REFERENCES public.requests(master_id) ON DELETE CASCADE;

-- Add “actionable_status” (Draft/In Progress/Complete)
ALTER TABLE public.all_actionables
  ADD COLUMN IF NOT EXISTS actionable_status single_line_text DEFAULT 'Draft';

-- Add target fields for request transition (don’t reuse all_actionables.status/stage)
ALTER TABLE public.all_actionables
  ADD COLUMN IF NOT EXISTS target_status single_line_text,
  ADD COLUMN IF NOT EXISTS target_stage  single_line_text;

-- OPTIONAL: if created_by is a bigint (master_key), don’t auto-fill with current_user text
-- leave it client-supplied or map explicitly (see function)



------------1) Trigger to attach on all_actionables (INSERT)
DROP TRIGGER IF EXISTS trg_validate_all_actionables_ins ON public.all_actionables;

CREATE TRIGGER trg_validate_all_actionables_ins
BEFORE INSERT ON public.all_actionables
FOR EACH ROW
EXECUTE FUNCTION public.fn_validate_all_actionables_insert();




--2) Updated function (partial-save + complete logic + type-safe)
-- DROP FUNCTION public.fn_validate_all_actionables_insert();

CREATE OR REPLACE FUNCTION public.fn_validate_all_actionables_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_json           jsonb;
    v_module         text;
    v_req_status     text;
    v_req_stage      text;
    v_valid          boolean := false;
    v_next_stage_map jsonb;
    v_request_id     bigint;
BEGIN
    --------------------------------------------------------------------
    -- Minimal mandatory fields for a draft
    --------------------------------------------------------------------
    IF NEW.request_subject IS NULL THEN
        RAISE EXCEPTION 'request_subject (requests.master_id) is required.';
    END IF;
    IF NEW.actionable_name IS NULL OR btrim(NEW.actionable_name) = '' THEN
        RAISE EXCEPTION 'actionable_name is required.';
    END IF;
    IF NEW.actionable_category IS NULL OR btrim(NEW.actionable_category) = '' THEN
        RAISE EXCEPTION 'actionable_category is required.';
    END IF;

    -- created_by: do NOT set current_user into bigint column.
    -- If you want to auto-map, uncomment this lookup by email/username:
    -- IF NEW.created_by IS NULL THEN
    --   SELECT u.master_id INTO NEW.created_by
    --   FROM public.users u
    --   WHERE u.email_address = current_user; -- or your mapping
    -- END IF;

    IF NEW.actionable_creation_time IS NULL THEN
        NEW.actionable_creation_time := now();
    END IF;

    --------------------------------------------------------------------
    -- Link to request: use FK master_id (BIGINT)
    --------------------------------------------------------------------
    SELECT r.master_id, r.module, r.status, r.stage
    INTO v_request_id, v_module, v_req_status, v_req_stage
    FROM public.requests r
    WHERE r.master_id = NEW.request_subject
    LIMIT 1;

    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'No matching request found for actionable with request_subject=%', NEW.request_subject;
    END IF;

    --------------------------------------------------------------------
    -- Load JSON config
    --------------------------------------------------------------------
    SELECT json_actionable_data
    INTO v_json
    FROM public.json_actionable
    ORDER BY master_id DESC
    LIMIT 1;

    IF v_json IS NULL THEN
        RAISE EXCEPTION 'JSON configuration missing in json_actionable.';
    END IF;

    --------------------------------------------------------------------
    -- PARTIAL SAVE (Draft/In Progress): only check that actionable exists for module
    --------------------------------------------------------------------
    -- If actionable_status is NULL, treat as 'Draft'
    IF NEW.actionable_status IS NULL THEN
        NEW.actionable_status := 'Draft';
    END IF;

    -- Is the actionable name valid for this module at all?
    v_valid := EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_json -> 'module' -> initcap(lower(v_module)) -> 'actionables') elem
        WHERE elem ->> 'Actionable Name' = NEW.actionable_name
    );

    IF NOT v_valid THEN
        RAISE EXCEPTION 'Actionable "%" not defined under module "%".',
            NEW.actionable_name, v_module;
    END IF;

    -- If only draft: stop here (don’t validate transitions)
    IF lower(NEW.actionable_status) IN ('draft', 'in progress') THEN
        RETURN NEW;
    END IF;

    --------------------------------------------------------------------
    -- COMPLETION PATH: validate category-specific rules
    --------------------------------------------------------------------
    IF lower(NEW.actionable_status) = 'complete' THEN

        -- Category: Update Status → must carry target_status/target_stage
        IF lower(NEW.actionable_category) = 'update status' THEN
            IF NEW.target_status IS NULL OR NEW.target_stage IS NULL THEN
                RAISE EXCEPTION 'target_status and target_stage are required to complete "Update Status" actionable.';
            END IF;

            -- Make sure actionable is valid at the request's current status/stage
            v_valid := EXISTS (
                SELECT 1
                FROM jsonb_array_elements(v_json -> 'module' -> initcap(lower(v_module)) -> 'actionables') elem
                WHERE elem ->> 'Actionable Name' = NEW.actionable_name
                  AND (
                       elem -> 'solution_status' -> v_req_status ? v_req_stage
                       OR elem -> 'solution_status' -> v_req_status IS NOT NULL
                  )
            );
            IF NOT v_valid THEN
                RAISE EXCEPTION
                    'Actionable "%" is not valid for module "%" at current state "%" / "%".',
                    NEW.actionable_name, v_module, v_req_status, v_req_stage;
            END IF;

            -- Validate allowed transition for the request
            v_next_stage_map :=
                v_json -> 'module' -> initcap(lower(v_module))
                       -> 'solution_status' -> v_req_status -> v_req_stage -> 'next_status_stage';

            IF v_next_stage_map IS NULL THEN
                RAISE EXCEPTION 'Transition rules missing for module "%", state "%"/"%".',
                    v_module, v_req_status, v_req_stage;
            END IF;

            v_valid := (
                v_next_stage_map ? NEW.target_status
                AND NEW.target_stage IN (
                    SELECT jsonb_array_elements_text(v_next_stage_map -> NEW.target_status)
                )
            );

            IF NOT v_valid THEN
                RAISE EXCEPTION
                    'Invalid transition: (%/%)->(%/%).',
                    v_req_status, v_req_stage, NEW.target_status, NEW.target_stage;
            END IF;

            -- If stage = Others → reason_for_hold required
            IF lower(NEW.target_stage) = 'others'
               AND (NEW.reason_for_hold IS NULL OR btrim(NEW.reason_for_hold) = '') THEN
                RAISE EXCEPTION 'Reason for Hold is required when target_stage = "Others".';
            END IF;

            -- ✅ Apply the transition to the request (since actionable is Complete)
            UPDATE public.requests
            SET status = NEW.target_status,
                stage  = NEW.target_stage,
                modified_time = now()
            WHERE master_id = v_request_id;
        END IF;

        -- Mark actionable closed timestamps if you keep them
        IF NEW.actionable_completion_time IS NULL THEN
            NEW.actionable_completion_time := now();
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;



-- 3) How to insert (Draft → Complete)

INSERT INTO public.all_actionables (
    request_subject,          -- FK to requests.master_id
    actionable_name,
    actionable_category,
    actionable_status         -- Draft or In Progress
) VALUES (
    10,
    'Hold Request',
    'Update Status',
    'Draft'
);

--Complete (and move request to next allowed state)
INSERT INTO public.all_actionables (
    request_subject,
    actionable_name,
    actionable_category,
    actionable_status,
    target_status,
    target_stage,
    reason_for_hold
) VALUES (
    10,
    'Hold Request',
    'Update Status',
    'Complete',
    'On Hold',
    'Customer Response Awaited',
    'Customer not responding'
);
