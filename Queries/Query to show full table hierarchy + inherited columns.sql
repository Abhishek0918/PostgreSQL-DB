WITH inheritance_info AS (
    SELECT 
        c.oid AS child_oid,
        c.relname AS child_table,
        p.relname AS parent_table
    FROM pg_inherits
    JOIN pg_class c ON pg_inherits.inhrelid = c.oid
    JOIN pg_class p ON pg_inherits.inhparent = p.oid
)
SELECT 
    child_table,
    parent_table,
    a.attname AS column_name,
    CASE 
        WHEN a.attinhcount > 0 THEN 'Inherited'
        ELSE 'Local'
    END AS column_origin,
    format_type(a.atttypid, a.atttypmod) AS data_type
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
LEFT JOIN inheritance_info i ON i.child_oid = c.oid
WHERE 
    a.attnum > 0 
    AND NOT a.attisdropped
    AND c.relkind = 'r'
ORDER BY 
    child_table, parent_table NULLS FIRST, column_origin DESC, a.attnum;
