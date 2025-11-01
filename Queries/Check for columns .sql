--Only local columns 
SELECT
    a.attname AS column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type
FROM pg_attribute a
WHERE a.attrelid = 'public.requests_problem'::regclass
  AND a.attnum > 0
  AND NOT a.attisdropped
  AND a.attinhcount = 0   
ORDER BY a.attnum;

-- all column 

SELECT column_name,data_type 
FROM information_schema.columns
  WHERE table_name = 'requests_problem';