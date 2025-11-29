-- public.universal_view2 source

CREATE OR REPLACE VIEW public.universal_view2
AS WITH status_tracking AS (
         WITH status_changes AS (
                 SELECT d.in_ref_master_table AS request_id,
                    d.new_value AS status,
                    d.in_added_time AS changed_time,
                    row_number() OVER (PARTITION BY d.in_ref_master_table, d.new_value ORDER BY d.in_added_time) AS rn
                   FROM data_logs_fields d
                  WHERE d.form_link_name::text = 'requests'::text AND d.field_value = 'status'::text AND d.new_value IS NOT NULL
                )
         SELECT status_changes.request_id,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = 'Queued'::text) AS queued_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = 'Backlog'::text) AS backlog_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = 'Received'::text) AS received_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = ANY (ARRAY['Assigned'::text, 'Open'::text])) AS assigned_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = 'In Progress'::text) AS in_progress_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = 'On Hold'::text) AS on_hold_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = 'Complete'::text) AS complete_timestamp,
            min(status_changes.changed_time::timestamp with time zone) FILTER (WHERE status_changes.status = ANY (ARRAY['Close'::text, 'Closed'::text])) AS closed_timestamp
           FROM status_changes
          WHERE status_changes.rn = 1
          GROUP BY status_changes.request_id
        ), dependent_childs AS (
         SELECT parent.immediate_parent,
            count(*) AS dependent_requests,
            count(*) FILTER (WHERE r_child.status::text = 'Complete'::text) AS closed_dependent_requests
           FROM ( SELECT rs.immediate_parent,
                    rs.ref_requests_record_id
                   FROM requests_services rs
                UNION ALL
                 SELECT rst.immediate_parent,
                    rst.ref_requests_record_id
                   FROM requests_staffing rst) parent
             JOIN requests r_child ON r_child.in_record_id = parent.ref_requests_record_id::bigint
          GROUP BY parent.immediate_parent
        )
 SELECT r1.in_added_time AS created_time,
    u1.user_name AS added_user,
    u1.email_id AS added_user_email,
    r1.in_record_id AS id,
    COALESCE(s1.root_parent, st1.root_parent) AS root_parent,
    COALESCE(r3.module, r3_staff.module) AS root_module,
    COALESCE(s1.immediate_parent, st1.immediate_parent) AS immediate_parent,
    COALESCE(r2.module, r2_staff.module) AS immediate_module,
    r1.module,
    r1.solution_type,
    r1.request_dependency,
    r1.summary,
    u1.user_name AS owner,
    u1.email_id AS owner_email,
    u1.id AS owner_id,
    u1.account_name AS owner_account,
    r1.status,
    r1.stage,
    m1.in_record_id AS sku_id,
    m1.sku_name AS microservice_name,
    COALESCE(p11.in_record_id, p12.in_record_id) AS practice_id,
    COALESCE(p11.practice_name_corporate_unit, p12.practice_name_corporate_unit) AS practice,
    COALESCE(s1.quantity, st1.quantity) AS quantity,
    r1.description,
    COALESCE(p1.reason_for_hold, s1.reason_for_hold) AS reason_for_hold,
    r1.attachments,
    null as file_id,
    null as file_name,
    null as file_size,
    null as file_type,
    COALESCE(u4.user_name, u5.user_name) AS root_owner,
    COALESCE(u4.account_name, u5.account_name) AS root_account,
    COALESCE(u2.id, u3.id) AS immediate_owner_id,
    COALESCE(u2.user_name, u3.user_name) AS immediate_owner,
    COALESCE(u2.email_id, u3.email_id) AS immediate_owner_email,
    COALESCE(u2.account_id, u3.account_id) AS immediate_account_id,
    COALESCE(u2.account_name, u3.account_name) AS immediate_account,
    COALESCE(r3.summary, r3_staff.summary) AS root_parent_request_subject,
    COALESCE(r2.summary, r2_staff.summary) AS immediate_parent_request_subject,
    dependent_childs.dependent_requests,
    dependent_childs.closed_dependent_requests,
    status_tracking.queued_timestamp,
    status_tracking.backlog_timestamp,
    status_tracking.received_timestamp,
    status_tracking.assigned_timestamp,
    status_tracking.in_progress_timestamp,
    status_tracking.on_hold_timestamp,
    status_tracking.complete_timestamp,
    status_tracking.closed_timestamp
   FROM requests r1
     LEFT JOIN status_tracking ON status_tracking.request_id = r1.in_record_id
     LEFT JOIN dependent_childs ON dependent_childs.immediate_parent::bigint = r1.in_record_id
     LEFT JOIN requests_problem p1 ON p1.ref_requests_record_id::bigint = r1.in_record_id
     LEFT JOIN requests_services s1 ON s1.ref_requests_record_id::bigint = r1.in_record_id
     LEFT JOIN practices p11 ON s1.practice::bigint = p11.in_record_id
     LEFT JOIN requests_staffing st1 ON st1.ref_requests_record_id::bigint = r1.in_record_id
     LEFT JOIN practices p12 ON st1.practice::bigint = p12.in_record_id
     LEFT JOIN services_sku m1 ON s1.ref_services_sku::bigint = m1.in_record_id
     LEFT JOIN users_universal u1 ON r1.owner::bigint = u1.id
     LEFT JOIN requests r2 ON s1.immediate_parent::bigint = r2.in_record_id
     LEFT JOIN users_universal u2 ON r2.owner::bigint = u2.id
     LEFT JOIN requests r3 ON s1.root_parent::bigint = r3.in_record_id
     LEFT JOIN users_universal u4 ON r3.owner::bigint = u4.id
     LEFT JOIN requests r2_staff ON st1.immediate_parent::bigint = r2_staff.in_record_id
     LEFT JOIN users_universal u3 ON r2_staff.owner::bigint = u3.id
     LEFT JOIN requests r3_staff ON st1.root_parent::bigint = r3_staff.in_record_id
     LEFT JOIN users_universal u5 ON r3_staff.owner::bigint = u5.id
  ORDER BY r1.in_record_id;

