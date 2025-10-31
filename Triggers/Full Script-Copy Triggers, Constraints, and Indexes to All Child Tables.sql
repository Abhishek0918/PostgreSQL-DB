-- =============================================================
-- FUNCTION: clone_all_properties_to_children
-- PURPOSE: Copy all NON-INHERITED properties from a parent table
--          to ALL its child tables in PostgreSQL inheritance.
--
-- WHAT IT COPIES:
--   • Triggers
--   • CHECK / UNIQUE / PRIMARY KEY / FOREIGN KEY constraints
--   • Indexes (non-constraint)
--   • Table & column comments
--
-- WHAT IT DOES NOT COPY (already inherited):
--   • Columns
--   • Data types
--   • NOT NULL (unless via constraint)
--
-- USAGE:
--   SELECT * FROM clone_all_properties_to_children('parent_table_name'::regclass);
--
-- RETURNS:
--   child_table | object_type | object_name | status  | message
-- =============================================================

CREATE OR REPLACE FUNCTION clone_all_properties_to_children(parent_table regclass)
RETURNS TABLE (
    child_table TEXT,
    object_type TEXT,
    object_name TEXT,
    status      TEXT,
    message     TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    child_rec   RECORD;  -- Holds each child table name
    sql_text    TEXT;    -- Dynamic SQL to execute
    rec         RECORD;  -- Generic loop record
    new_name    TEXT;    -- New object name with suffix
BEGIN

    RAISE NOTICE '=== START: CLONING ALL NON-INHERITED PROPERTIES FROM % ===', parent_table;

    -- =============================================================
    -- LOOP: Iterate over every child table that inherits from parent
    -- =============================================================
    FOR child_rec IN
        SELECT inhrelid::regclass::TEXT AS child_name
        FROM pg_inherits
        WHERE inhparent = parent_table
    LOOP
        RAISE NOTICE '  → PROCESSING CHILD TABLE: %', child_rec.child_name;

        -- =============================================================
        -- 1. TRIGGERS
        --    - Copy all non-system triggers
        --    - Rename: original_name_on_childname
        -- =============================================================
        FOR rec IN
            SELECT tgname, pg_get_triggerdef(oid) AS def
            FROM pg_trigger
            WHERE tgrelid = parent_table
              AND NOT tgisinternal                    -- Skip internal triggers
              AND tgname NOT LIKE 'ri_%'              -- Skip basic FK triggers (optional)
        LOOP
            -- Replace parent table name with child name in trigger definition
            sql_text := replace(rec.def, parent_table::TEXT, child_rec.child_name);

            -- Build unique trigger name: trg_name_on_child1
            new_name := rec.tgname || '_on_' || split_part(child_rec.child_name, '.', -1);

            -- Replace old trigger name with new one in SQL
            sql_text := regexp_replace(
                sql_text,
                'TRIGGER\s+' || quote_ident(rec.tgname) || '\s',
                'TRIGGER ' || quote_ident(new_name) || ' ',
                'i'
            );

            BEGIN
                EXECUTE sql_text;
                RETURN QUERY SELECT
                    child_rec.child_name,
                    'TRIGGER'::TEXT,
                    new_name,
                    'CREATED'::TEXT,
                    ''::TEXT;
            EXCEPTION
                WHEN duplicate_object THEN
                    RETURN QUERY SELECT child_rec.child_name, 'TRIGGER', new_name, 'SKIPPED', 'Already exists';
                WHEN OTHERS THEN
                    RETURN QUERY SELECT child_rec.child_name, 'TRIGGER', new_name, 'ERROR', SQLERRM;
            END;
        END LOOP;

        -- =============================================================
        -- 2. CONSTRAINTS: CHECK, UNIQUE, PRIMARY KEY, FOREIGN KEY
        --    - Only copy constraints NOT marked as inherited
        -- =============================================================
        FOR rec IN
            SELECT conname, pg_get_constraintdef(oid) AS def, contype
            FROM pg_constraint
            WHERE conrelid = parent_table
              AND contype IN ('c', 'u', 'p', 'f')   -- c=CHECK, u=UNIQUE, p=PK, f=FK
              AND coninhcount = 0                   -- NOT inherited
        LOOP
            -- Build new constraint name
            new_name := rec.conname || '_on_' || split_part(child_rec.child_name, '.', -1);

            -- Generate ALTER TABLE ... ADD CONSTRAINT
            sql_text := format(
                'ALTER TABLE %I ADD CONSTRAINT %I %s',
                child_rec.child_name,
                new_name,
                rec.def
            );

            DECLARE
                ctype_text TEXT := CASE rec.contype
                    WHEN 'c' THEN 'CHECK'
                    WHEN 'u' THEN 'UNIQUE'
                    WHEN 'p' THEN 'PRIMARY KEY'
                    WHEN 'f' THEN 'FOREIGN KEY'
                END;
            BEGIN
                EXECUTE sql_text;
                RETURN QUERY SELECT
                    child_rec.child_name,
                    ctype_text,
                    new_name,
                    'CREATED',
                    '';
            EXCEPTION
                WHEN duplicate_object THEN
                    RETURN QUERY SELECT child_rec.child_name, ctype_text, new_name, 'SKIPPED', 'Already exists';
                WHEN OTHERS THEN
                    RETURN QUERY SELECT child_rec.child_name, ctype_text, new_name, 'ERROR', SQLERRM;
            END;
        END LOOP;

        -- =============================================================
        -- 3. INDEXES (non-constraint indexes only)
        --    - Skip PK indexes (already covered by constraint)
        -- =============================================================
        FOR rec IN
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename = parent_table::TEXT
              AND schemaname = current_schema()           -- Respect search_path
              AND indexdef NOT ILIKE '%PRIMARY KEY%'      -- Avoid duplicate PK index
        LOOP
            sql_text := replace(rec.indexdef, parent_table::TEXT, child_rec.child_name);
            new_name := rec.indexname || '_on_' || split_part(child_rec.child_name, '.', -1);

            sql_text := regexp_replace(
                sql_text,
                'INDEX\s+' || quote_ident(rec.indexname),
                'INDEX ' || quote_ident(new_name),
                'i'
            );

            BEGIN
                EXECUTE sql_text;
                RETURN QUERY SELECT child_rec.child_name, 'INDEX', new_name, 'CREATED', '';
            EXCEPTION
                WHEN duplicate_object THEN
                    RETURN QUERY SELECT child_rec.child_name, 'INDEX', new_name, 'SKIPPED', 'Already exists';
                WHEN OTHERS THEN
                    RETURN QUERY SELECT child_rec.child_name, 'INDEX', new_name, 'ERROR', SQLERRM;
            END;
        END LOOP;

        -- =============================================================
        -- 4. COMMENTS: Table-level and Column-level
        -- =============================================================
        -- Table comment
        DECLARE
            table_comment TEXT;
        BEGIN
            table_comment := obj_description(parent_table);
            IF table_comment IS NOT NULL THEN
                sql_text := format('COMMENT ON TABLE %I IS %L', child_rec.child_name, table_comment);
                EXECUTE sql_text;
                RETURN QUERY SELECT child_rec.child_name, 'COMMENT', 'TABLE', 'COPIED', '';
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT child_rec.child_name, 'COMMENT', 'TABLE', 'ERROR', SQLERRM;
        END;

        -- Column comments
        FOR rec IN
            SELECT 
                a.attname,
                pg_catalog.col_description(parent_table, a.attnum) AS col_comment
            FROM pg_attribute a
            WHERE a.attrelid = parent_table
              AND a.attnum > 0
              AND NOT a.attisdropped
              AND pg_catalog.col_description(parent_table, a.attnum) IS NOT NULL
        LOOP
            sql_text := format(
                'COMMENT ON COLUMN %I.%I IS %L',
                child_rec.child_name,
                rec.attname,
                rec.col_comment
            );
            BEGIN
                EXECUTE sql_text;
                RETURN QUERY SELECT
                    child_rec.child_name,
                    'COMMENT',
                    'COL:' || rec.attname,
                    'COPIED',
                    '';
            EXCEPTION WHEN OTHERS THEN
                RETURN QUERY SELECT child_rec.child_name, 'COMMENT', 'COL:' || rec.attname, 'ERROR', SQLERRM;
            END;
        END LOOP;

        RAISE NOTICE '  → FINISHED child: %', child_rec.child_name;
    END LOOP;

    RAISE NOTICE '=== CLONE ALL PROPERTIES COMPLETE ===';
    RETURN;
END;
$$;


-- Replace with your actual parent table
SELECT * FROM clone_all_properties_to_children('requests_problem'::regclass);