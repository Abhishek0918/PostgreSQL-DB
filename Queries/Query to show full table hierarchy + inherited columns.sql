WITH inheritance_info AS (
    SELECT 
        c.oid AS child_oid,
        c.relname AS child_table,
        n_child.nspname AS child_schema,
        p.relname AS parent_table,
        n_parent.nspname AS parent_schema
    FROM pg_inherits
    JOIN pg_class c ON pg_inherits.inhrelid = c.oid
    JOIN pg_namespace n_child ON c.relnamespace = n_child.oid
    JOIN pg_class p ON pg_inherits.inhparent = p.oid
    JOIN pg_namespace n_parent ON p.relnamespace = n_parent.oid
    WHERE n_child.nspname IN ('auth', 'public')
       OR n_parent.nspname IN ('auth', 'public')
)
SELECT 
    c.relnamespace::regnamespace AS table_schema,
    c.relname AS table_name,
    i.parent_schema,
    i.parent_table,
    a.attname AS column_name,
    CASE 
        WHEN a.attinhcount > 0 THEN 'Inherited'
        ELSE 'Local'
    END AS column_origin,
    format_type(a.atttypid, a.atttypmod) AS data_type
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
LEFT JOIN inheritance_info i ON i.child_oid = c.oid
WHERE 
    a.attnum > 0 
    AND NOT a.attisdropped
    AND c.relkind = 'r'
    AND n.nspname IN ('auth', 'public')
ORDER BY 
    table_schema,
    table_name, 
    parent_schema NULLS FIRST, 
    parent_table NULLS FIRST, 
    column_origin DESC, 
    a.attnum;