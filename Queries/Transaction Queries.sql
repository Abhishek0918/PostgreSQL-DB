--- FOR EACH TRANSACTION ---

-- Start a transaction
BEGIN;

-- Your schema change or risky operations
CREATE TABLE test_table (
    id SERIAL PRIMARY KEY,
    name TEXT
);

-- Example risky update
UPDATE employees SET salary = salary * 1.2 WHERE department = 'Sales';

-- Check your results
SELECT * FROM employees WHERE department = 'Sales';

-- If everything looks good
COMMIT;

-- If you made a mistake or want to cancel everything
ROLLBACK;

--------------------------SAVEPOINT for Partial Rollback--------------------------

BEGIN;

ALTER TABLE employees ADD COLUMN backup_flag BOOLEAN;

SAVEPOINT step1;

UPDATE employees SET backup_flag = TRUE;

-- Something went wrong
ROLLBACK TO step1;  -- Undo only changes after this savepoint

COMMIT;


/*
====================================================
 🧩 SAFE TRANSACTION TEMPLATE – POSTGRESQL
 Use this whenever creating, altering, deleting,
 or dropping tables / data to ensure rollback safety
====================================================
*/

-- 🟢 STEP 1: Start the transaction
BEGIN;

-- 🧠 (Optional) Create a savepoint for partial rollback
SAVEPOINT initial_state;

-- ⚙️ STEP 2: Perform your operations here
-- ==========================================

-- Example: create or alter tables
-- CREATE TABLE my_table (...);
-- ALTER TABLE employees ADD COLUMN test_col TEXT;
-- DROP TABLE IF EXISTS temp_table;

-- Example: modify data
-- UPDATE employees SET salary = salary * 1.1 WHERE department = 'Sales';
-- DELETE FROM temp_data WHERE created_at < NOW() - INTERVAL '30 days';

-- ==========================================

-- 🧩 STEP 3: Verify results before committing
-- (use SELECT statements to check what changed)
-- SELECT * FROM employees LIMIT 10;

-- 🟡 STEP 4: Decide what to do
-- ============================
-- If everything looks good:
-- COMMIT;

-- If you made a mistake or changed your mind:
-- ROLLBACK;

-- (Optional) If you set a savepoint and want to revert only part of the work:
-- ROLLBACK TO SAVEPOINT initial_state;
-- then continue testing...
-- COMMIT;



