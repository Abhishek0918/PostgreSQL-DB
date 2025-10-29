--If you want more granular logging (e.g., "This run is for parent X, skipping Y triggers")



CREATE OR REPLACE FUNCTION clone_triggers_to_children(parent_table regclass)
RETURNS BOOLEAN
LANGUAGE plpgsql
SET search_path = public  -- Adjust if your schema differs
AS $$  
DECLARE
    child_rec RECORD;
    trig_rec RECORD;
    create_trig_sql TEXT;
    original_trig_name TEXT;
    success_count INTEGER := 0;
    skip_count INTEGER := 0;
    total_children INTEGER := 0;
    existing_trig_count INTEGER := 0;
BEGIN
    -- Enhanced: Log the exact parent being processed
    RAISE NOTICE '=== CLONING TRIGGERS FOR PARENT: % (started at %%) ===', parent_table, clock_timestamp();

    -- Count children for logging
    SELECT COUNT(*) INTO total_children
    FROM pg_inherits
    WHERE inhparent = parent_table;
    IF total_children = 0 THEN
        RAISE NOTICE 'No child tables found for parent %', parent_table;
        RETURN TRUE;
    END IF;
    RAISE NOTICE 'Found % child table(s) for parent %', total_children, parent_table;

    -- Loop over child tables
    FOR child_rec IN
        SELECT inhrelid::regclass::text AS child_name
        FROM pg_inherits
        WHERE inhparent = parent_table
    LOOP
        -- Decrement for loop logging (fixed: use a separate counter)
        total_children := total_children - 1;
        RAISE NOTICE 'Processing child table: % (remaining: %)', child_rec.child_name, total_children;

        -- Count existing triggers on this child for context
        SELECT COUNT(*) INTO existing_trig_count
        FROM pg_trigger
        WHERE tgrelid = child_rec.child_name::regclass
          AND NOT tgisinternal
          AND NOT tgname ~ '^ri_';
        RAISE NOTICE '  -> Child % already has % non-system triggers', child_rec.child_name, existing_trig_count;

        -- Loop over parent's non-system triggers
        FOR trig_rec IN
            SELECT
                tgname AS original_name,
                pg_get_triggerdef(oid) AS trigger_def
            FROM pg_trigger
            WHERE tgrelid = parent_table
              AND NOT tgisinternal  -- Skip system triggers
              AND NOT tgname ~ '^ri_'  -- Optional: Skip basic FK triggers if desired
        LOOP
            -- Build new CREATE TRIGGER SQL: Replace table name and rename trigger
            create_trig_sql := replace(
                trig_rec.trigger_def,
                parent_table::text,  -- Replace old table
                child_rec.child_name  -- With new table
            );
           
            -- Extract original name and build new name (e.g., orig_trig_on_child_tbl)
            original_trig_name := trig_rec.original_name;
            create_trig_sql := replace(
                create_trig_sql,
                'TRIGGER ' || original_trig_name || ' ',
                'TRIGGER ' || original_trig_name || '_on_' || split_part(child_rec.child_name::text, '.', -1) || ' '  -- Append suffix
            );
            -- Execute with error handling
            BEGIN
                EXECUTE create_trig_sql;
                RAISE NOTICE '  -> Created: % on %', original_trig_name || '_on_' || split_part(child_rec.child_name::text, '.', -1), child_rec.child_name;
                success_count := success_count + 1;
            EXCEPTION
                WHEN duplicate_object THEN
                    RAISE NOTICE '  -> Skipped (already exists): % on %', original_trig_name, child_rec.child_name;  -- Changed to NOTICE for visibility
                    skip_count := skip_count + 1;
                WHEN OTHERS THEN
                    RAISE WARNING '  -> Failed to create % on %: %', original_trig_name, child_rec.child_name, SQLERRM;
            END;
        END LOOP;
    END LOOP;
    RAISE NOTICE '=== CLONE COMPLETE FOR %: % new triggers, % skips across % children (ended at %%) ===', 
                 parent_table, success_count, skip_count, (SELECT COUNT(DISTINCT inhrelid) FROM pg_inherits WHERE inhparent = parent_table), clock_timestamp();
    RETURN TRUE;
END;
  $$;