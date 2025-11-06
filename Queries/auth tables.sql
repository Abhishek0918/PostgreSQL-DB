DROP TABLE if exists auth.user_otps;

CREATE TABLE auth.user_otps (
    user_id text NOT NULL,
    created_time timestamp DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- auth.user_otps foreign keys

ALTER TABLE auth.user_otps
ADD CONSTRAINT user_otps_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users ("email_address") ON DELETE CASCADE ON UPDATE CASCADE;

DROP TABLE if exists auth.user_sessions;

CREATE TABLE auth.user_sessions (
    user_id text NOT NULL,
    created_time timestamp DEFAULT CURRENT_TIMESTAMP NOT NULL,
    session_cookie jsonb NOT NULL,
    id bigserial NOT NULL,
    CONSTRAINT user_sessions_id_key UNIQUE (id),
    CONSTRAINT user_sessions_pkey PRIMARY KEY (
        user_id,
        session_cookie,
        created_time
    )
);

-- auth.user_sessions foreign keys

ALTER TABLE auth.user_sessions
ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users ("email_address") ON DELETE CASCADE ON UPDATE CASCADE;

DROP TABLE if exists auth.user_session_refresh_token;

CREATE TABLE auth.user_session_refresh_token (
	user_id bigserial NOT NULL,
	created_time timestamp DEFAULT CURRENT_TIMESTAMP NOT NULL,
	expiry_time timestamp DEFAULT (CURRENT_TIMESTAMP + '30 days'::interval) NOT NULL,
	is_revoked bool DEFAULT false NOT NULL,
	"token" uuid DEFAULT gen_random_uuid() NOT NULL,
	CONSTRAINT user_session_refresh_token_token_key UNIQUE (token)
);

-- auth.user_session_refresh_token foreign keys

ALTER TABLE auth.user_session_refresh_token
ADD CONSTRAINT user_session_refresh_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.user_sessions (id) ON DELETE CASCADE ON UPDATE CASCADE;