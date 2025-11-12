CREATE TABLE public.actionables_reference (
    module text,
    status text,
    stage text,
    category text,
    actionable_name text,
    PRIMARY KEY (module, status, stage, category, actionable_name)
);



INSERT INTO public.actionables_reference (module, status, stage, category, actionable_name)
SELECT
    mod_key,
    stat.key AS status,
    stg.key  AS stage,
    cat.key  AS category,
    act.value::text AS actionable_name
FROM actionables_execution_metadata aem
CROSS JOIN LATERAL jsonb_each(aem.actionable_config -> 'module') AS m(mod_key, mod_val)
CROSS JOIN LATERAL jsonb_each(mod_val -> 'solution_status') AS stat
CROSS JOIN LATERAL jsonb_each(stat.value) AS stg
CROSS JOIN LATERAL jsonb_each(stg.value -> 'actionable_categories') AS cat
CROSS JOIN LATERAL jsonb_array_elements_text(cat.value) AS act;

select * from actionables_reference;