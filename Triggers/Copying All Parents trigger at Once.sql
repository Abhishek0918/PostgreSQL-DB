/*-- One-time batch: Clone for ALL parents with children
--If you have multiple parents and want to process them all (e.g., after schema changes), 
you can't call the function once for "all"—it's per-parent. But you can wrap it in a simple batch script to loop 
over all parents:*/

DO $$  
DECLARE
    parent_rec RECORD;
BEGIN
    FOR parent_rec IN
        SELECT DISTINCT inhparent::regclass::text AS parent_name
        FROM pg_inherits
        WHERE inhparent IN (  -- Or remove this for truly all
            SELECT oid FROM pg_class WHERE relkind = 'r'  -- User tables only
        )
    LOOP
        RAISE NOTICE '=== BATCH: Starting on parent % ===', parent_rec.parent_name;
        PERFORM clone_triggers_to_children(parent_rec.parent_name::regclass);
        RAISE NOTICE '=== BATCH: Finished parent % ===', parent_rec.parent_name;
    END LOOP;
END   $$;