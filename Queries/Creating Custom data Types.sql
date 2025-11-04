-----Function for Sanitizing the texts

CREATE OR REPLACE FUNCTION no_emoji(value text, max_length int DEFAULT 250)
RETURNS boolean AS $$
DECLARE
  cleaned text;
BEGIN
  --Trim extra spaces from start & end
  cleaned := trim(value);

  /*
    - Not empty after trimming
    - No emojis (U+D800–U+DFFF)
    - Allows letters, digits, math & punctuation symbols
    - Enforces max_length
  */
  RETURN cleaned ~* format(
    '^(?!\s*$)(?!.*[\uD800-\uDFFF])[\s\S]{1,%s}$',
    max_length
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- Recreate the domain with the new rule
CREATE DOMAIN single_line_text AS varchar(255)
  CHECK (
    no_emoji(VALUE, 255)
    AND VALUE !~ '[\r\n]'
  );


-- Multiline Text → up to 60,000 chars
CREATE DOMAIN multiline_text AS varchar(60000)
  CHECK (no_emoji(VALUE, 60000));

-- Multiline HTML → up to 60,000 chars
CREATE DOMAIN multiline_html AS varchar(60000)
  CHECK (no_emoji(VALUE, 60000));


 --Function for  Validation Phone Number

CREATE OR REPLACE FUNCTION validate_phone_number(p_phone TEXT)
RETURNS BOOLEAN AS $$
BEGIN
   -- Validate format: +<country_code> <10-digit-number>
    IF p_phone ~ '^\+[0-9]{1,3}\s[0-9]{10}$' THEN
        RETURN TRUE;
    ELSE
        RAISE EXCEPTION 'Invalid phone number format. Expected format: +CCC XXXXXXXXXX (e.g., +91 1234567891)';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE DOMAIN phone_number AS TEXT
CHECK (validate_phone_number(VALUE));

--City — domain
CREATE DOMAIN city AS varchar(100)
  CHECK (
    no_emoji(VALUE, 100)
    AND VALUE ~ '^[A-Za-z\s\.\-]+$'  -- only letters, spaces, dots, hyphens
  );

--State — domain
CREATE DOMAIN state AS varchar(100)
  CHECK (
    no_emoji(VALUE, 100)
    AND VALUE ~ '^[A-Za-z\s\.\-]+$'
  );

-- Postal Code — domain
CREATE DOMAIN postal_code AS varchar(20)
  CHECK (
    no_emoji(VALUE, 20)
    AND VALUE ~ '^[A-Za-z0-9\s\-]+$'  -- allows alphanumeric + space + hyphen
  );

--Country Domain
CREATE DOMAIN country AS varchar(100)
  CHECK (
    no_emoji(VALUE, 100)
    AND VALUE ~ '^[A-Za-z\s\.\-]+$'
  );

CREATE TYPE address AS (
    address_line_1 varchar(500) ,
    address_line_2 varchar(500) ,  -- optional
    city city,
    state state,
    postal_code postal_code,
    country country
);



