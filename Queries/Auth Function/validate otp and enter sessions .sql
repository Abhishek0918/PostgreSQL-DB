CREATE OR REPLACE FUNCTION auth.validate_otp_create_session(
    p_user_id TEXT,                -- email
    p_generated_code TEXT,         -- OTP entered by user
    p_session_cookie JSONB,        -- session cookie to store
    p_refresh_token TEXT,          -- newly generated refresh token
    p_refresh_expiry TIMESTAMPTZ   -- expiry time
)
RETURNS BIGINT                    -- returns session_id
LANGUAGE plpgsql
AS $$
DECLARE
    v_valid_code TEXT;
    v_attempt_count INTEGER;
    v_session_id BIGINT;
BEGIN
    ---------------------------------------------------------
    -- 1️⃣ Get OTP row
    ---------------------------------------------------------
    SELECT valid_code, attempt_count
    INTO v_valid_code, v_attempt_count
    FROM auth.user_otps
    WHERE user_id = p_user_id
      AND generated_code = p_generated_code
    ORDER BY created_time DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid OTP';
    END IF;

    ---------------------------------------------------------
    -- 2️⃣ Validate OTP
    -- valid_code is TEXT, so check 'true'
    ---------------------------------------------------------
    IF v_valid_code IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'OTP expired or invalid';
    END IF;

    ---------------------------------------------------------
    -- 3️⃣ Mark OTP as used (valid_code = 'false')
    ---------------------------------------------------------
    UPDATE auth.user_otps
    SET valid_code = 'false'
    WHERE user_id = p_user_id
      AND generated_code = p_generated_code;

    ---------------------------------------------------------
    -- 4️⃣ Create session (returns BIGSERIAL id)
    ---------------------------------------------------------
    INSERT INTO auth.user_sessions(
        user_id,
        created_time,
        session_cookie
    )
    VALUES(
        p_user_id,
        NOW(),
        p_session_cookie
    )
    RETURNING id INTO v_session_id;

    ---------------------------------------------------------
    -- 5️⃣ Insert refresh token (FK uses session_id!)
    ---------------------------------------------------------
    INSERT INTO auth.user_session_refresh_token(
        user_id,
        created_time,
        expiry_time,
        is_revoked,
        token
    )
    VALUES (
        v_session_id,         -- FK to user_sessions.id
        NOW(),
        p_refresh_expiry,
        FALSE,
        p_refresh_token
    );

    ---------------------------------------------------------
    -- 6️⃣ Return session_id
    ---------------------------------------------------------
    RETURN v_session_id;

END;
$$;
