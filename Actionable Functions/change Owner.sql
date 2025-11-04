--------------------------------------------- change Owner-------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ac_change_request_owner(
    request_table TEXT,
    p_ticket_id BIGINT,
    new_owner TEXT
) RETURNS VOID AS $$
BEGIN
    -- Check if new_owner exists in users table
    IF NOT EXISTS (SELECT 1 FROM "users" WHERE "master_key" = new_owner) THEN
        RAISE EXCEPTION 'New owner does not exist in users table';
    END IF;

    -- Update the owner in the specified request table
    IF request_table = 'requests_problem' THEN
        UPDATE "requests_problem"
        SET "owner" = new_owner
        WHERE "ticket_id" = p_ticket_id
          AND EXISTS (SELECT 1 FROM "users" WHERE "master_key" = "requests_problem"."owner");
    ELSIF request_table = 'requests_delivery' THEN
        UPDATE "requests_delivery"
        SET "owner" = new_owner
        WHERE "ticket_id" = p_ticket_id
          AND EXISTS (SELECT 1 FROM "users" WHERE "master_key" = "requests_delivery"."owner");
    ELSIF request_table = 'requests_people' THEN
        UPDATE "requests_people"
        SET "owner" = new_owner
        WHERE "ticket_id" = p_ticket_id
          AND EXISTS (SELECT 1 FROM "users" WHERE "master_key" = "requests_people"."owner");
    ELSE
        RAISE EXCEPTION 'Invalid request table name';
    END IF;
END;
$$ LANGUAGE plpgsql;






SELECT public.fn_ac_change_request_owner(
    'requests_problem'::text,
    789456::bigint,         -- Replace 12345 with the actual ticket_id
    'users_internalayush'::text          -- Replace 'ayush' with the new owner's master_key
);
