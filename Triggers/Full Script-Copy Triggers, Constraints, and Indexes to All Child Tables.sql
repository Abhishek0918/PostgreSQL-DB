DO
$$
DECLARE
    parent_table TEXT := 'parent_table';  -- 🔧 change this to your actual parent table name
    child RECORD;
    trg RECORD;
    chk RECORD;
    idx RECORD;
BEGIN
    -------------------------------------------------------------------------
    --   LOOP THROUGH ALL CHILD TABLES OF THE PARENT
    -------------------------------------------------------------------------
    FOR child IN 
        SELECT c.relname AS child_table
        FROM pg_inherits
        JOIN pg_class c ON c.oid = pg_inherits.inhrelid
        JOIN pg_class p ON p.oid = pg_inherits.inhparent
        WHERE p.relname = parent_table
    LOOP
        RAISE NOTICE 'Processing child table: %', child.child_table;

        ---------------------------------------------------------------------
        --  COPY TRIGGERS FROM PARENT TO CHILD
        ---------------------------------------------------------------------
        FOR trg IN 
            SELECT tgname, tgfoid::regprocedure, tgtype
            FROM pg_trigger
            WHERE tgrelid = parent_table::regclass
              AND NOT tgisinternal
        LOOP
            BEGIN
                EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I;', trg.tgname, child.child_table);

                EXECUTE format(
                    'CREATE TRIGGER %I %s ON %I EXECUTE FUNCTION %s;',
                    trg.tgname,
                    CASE 
                        WHEN trg.tgtype & 1 = 1 THEN 'BEFORE'
                        WHEN trg.tgtype & 2 = 2 THEN 'AFTER'
                        ELSE 'INSTEAD OF'
                    END,
                    child.child_table,
                    trg.tgfoid::regprocedure
                );

                RAISE NOTICE '✅ Trigger % copied to %', trg.tgname, child.child_table;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '⚠️ Failed to copy trigger % to table %', trg.tgname, child.child_table;
            END;
        END LOOP;

        ---------------------------------------------------------------------
        --  COPY CHECK CONSTRAINTS FROM PARENT TO CHILD
        ---------------------------------------------------------------------
        FOR chk IN 
            SELECT conname, pg_get_constraintdef(oid) AS definition
            FROM pg_constraint
            WHERE conrelid = parent_table::regclass
              AND contype = 'c'
        LOOP
            BEGIN
                EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I;', child.child_table, chk.conname);
                EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I %s;', child.child_table, chk.conname, chk.definition);
                RAISE NOTICE '✅ Check constraint % copied to %', chk.conname, child.child_table;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '⚠️ Failed to copy constraint % to %', chk.conname, child.child_table;
            END;
        END LOOP;

        ---------------------------------------------------------------------
        --  COPY INDEXES FROM PARENT TO CHILD
        ---------------------------------------------------------------------
        FOR idx IN
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename = parent_table
        LOOP
            BEGIN
                EXECUTE format('DROP INDEX IF EXISTS %I_%I_idx;', child.child_table, idx.indexname);
                EXECUTE format(
                    '%s;',
                    replace(idx.indexdef, parent_table, child.child_table)
                );
                RAISE NOTICE '✅ Index % copied to %', idx.indexname, child.child_table;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '⚠️ Failed to copy index % to %', idx.indexname, child.child_table;
            END;
        END LOOP;

    END LOOP;
END;
$$;
