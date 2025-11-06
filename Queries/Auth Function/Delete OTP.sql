CREATE OR REPLACE FUNCTION auth.fn_consume_otp(
    p_user_id TEXT,
    p_otp_code BIGINT
)
RETURNS TABLE (
    matched BOOLEAN,
    is_expired BOOLEAN,
    deleted_count INTEGER,
    otp_created_time TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_created TIMESTAMP;
    v_correct BOOLEAN := FALSE;
    v_is_expired BOOLEAN := FALSE;
BEGIN
    -- ✅ Fetch OTP row
    SELECT created_time
    INTO v_created
    FROM auth.user_otps
    WHERE user_id = p_user_id;

    -- ✅ If no OTP found
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, FALSE, 0, NULL;
        RETURN;
    END IF;

    -- ✅ Check expiry (2 minutes)
    IF v_created < NOW() - INTERVAL '2 minutes' THEN
        v_is_expired := TRUE;
    END IF;

    -- ✅ Check correctness (only if NOT expired)
    IF NOT v_is_expired THEN
        SELECT EXISTS (
            SELECT 1 FROM auth.user_otps
            WHERE user_id = p_user_id
            AND otp_code = p_otp_code
        ) INTO v_correct;
    END IF;

    -- ✅ Delete OTP (always delete on attempt)
    DELETE FROM auth.user_otps
    WHERE user_id = p_user_id;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    -- ✅ Return result
    RETURN QUERY SELECT 
        v_correct AS matched,
        v_is_expired AS is_expired,
        deleted_count,
        v_created AS otp_created_time;

END;
$$;
