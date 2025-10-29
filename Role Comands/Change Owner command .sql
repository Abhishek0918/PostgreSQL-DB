/********************************************************************
PostgreSQL Ownership and Role Management Script
---------------------------------------------------------------------
This script performs the following administrative actions:
  1. Sets and resets roles.
  2. Changes ownership of all tables, sequences, views,
     functions, and procedures to a specified user ('admin').
  3. Provides inline documentation for understanding.
*********************************************************************/


/************************************************************
ROLE MANAGEMENT COMMANDS
************************************************************/

-- Set the active role to a specific user (replace 'username')
SET ROLE username;

-- Reset to the original role
RESET ROLE;

-- Check the current user and session user
SELECT current_user, session_user;

-- Change the owner of a specific table to 'admin'
ALTER TABLE table_name OWNER TO admin;



/************************************************************
CHANGE OWNER OF ALL TABLES TO 'admin'
************************************************************/
DO
$$
DECLARE
    r RECORD;
BEGIN
    -- Loop through all user-defined tables (excluding system schemas)
    FOR r IN 
        SELECT schemaname, tablename 
        FROM pg_tables 
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    LOOP
        -- Dynamically change ownership to 'admin'
        EXECUTE format('ALTER TABLE %I.%I OWNER TO admin;', r.schemaname, r.tablename);
    END LOOP;
END;
$$;



/************************************************************
CHANGE OWNER OF A SPECIFIC TABLE (EXAMPLE)
************************************************************/
-- You can use this for an individual table if needed
ALTER TABLE schema_name.table_name OWNER TO admin;



/************************************************************
CHANGE OWNER OF ALL SEQUENCES TO 'admin'
************************************************************/
DO
$$
DECLARE
    r RECORD;
BEGIN
    -- Select all user-defined sequences
    FOR r IN
        SELECT n.nspname AS schemaname, c.relname AS sequencename
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'S'  -- Only sequences
          AND n.nspname NOT IN ('pg_catalog', 'information_schema')
    LOOP
        -- Change sequence ownership to 'admin'
        EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO admin;', r.schemaname, r.sequencename);
    END LOOP;
END;
$$;



/************************************************************
CHANGE OWNER OF ALL VIEWS TO 'admin'
************************************************************/
DO
$$
DECLARE
    r RECORD;
BEGIN
    -- Select all non-system views
    FOR r IN 
        SELECT table_schema, table_name 
        FROM information_schema.views
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    LOOP
        -- Change view ownership
        EXECUTE format('ALTER VIEW %I.%I OWNER TO admin;', r.table_schema, r.table_name);
    END LOOP;
END;
$$;



/************************************************************
CHANGE OWNER OF ALL FUNCTIONS TO 'admin'
************************************************************/
DO
$$
DECLARE
    r RECORD;
BEGIN
    -- Select all user-defined functions
    FOR r IN
        SELECT n.nspname AS routine_schema, 
               p.proname AS routine_name
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND p.prokind = 'f'  -- 'f' = function
    LOOP
        -- Change ownership (note: adjust args if functions have parameters)
        EXECUTE format('ALTER FUNCTION %I.%I() OWNER TO admin;', r.routine_schema, r.routine_name);
    END LOOP;
END;
$$;



/************************************************************
CHANGE OWNER OF ALL PROCEDURES TO 'admin'
************************************************************/
DO
$$
DECLARE
    r RECORD;
BEGIN
    -- Select all user-defined stored procedures
    FOR r IN
        SELECT n.nspname AS schema_name,
               p.proname AS proc_name,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND p.prokind = 'p'  -- 'p' = procedure
    LOOP
        -- Change procedure ownership to 'admin'
        EXECUTE format('ALTER PROCEDURE %I.%I(%s) OWNER TO admin;', 
                       r.schema_name, r.proc_name, r.args);
    END LOOP;
END;
$$;
