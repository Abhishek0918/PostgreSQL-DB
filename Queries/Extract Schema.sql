
SELECT json_agg(
  json_build_object(
    'schema_name', table_schema,
    'table_name', table_name,
    'column_name', column_name,
    'column_type', data_type
  )
)
FROM information_schema.columns
WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'pg_toast');