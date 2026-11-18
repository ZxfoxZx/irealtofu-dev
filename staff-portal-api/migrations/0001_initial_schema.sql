
-- ============================================================
-- CREATE: ULTIMATE AUTOMATION
-- STAFF PORTAL - INITIAL DATABASE SCHEMA
-- Migration: 0001
-- ============================================================

-- ------------------------------------------------------------
-- 1. STAFF ACCOUNTS
-- Discord identities are the source of staff identity.
-- Portal access is independently suspendable.
-- Portal permissions are verified against Discord roles.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_accounts (
    discord_user_id TEXT PRIMARY KEY,

    discord_username TEXT NOT NULL,
    display_name TEXT,
    avatar_hash TEXT,

    portal_access_status TEXT NOT NULL DEFAULT 'active'
        CHECK (portal_access_status IN ('active', 'suspended')),

    suspension_type TEXT
        CHECK (suspension_type IS NULL OR
               suspension_type IN ('temporary', 'permanent')),

    suspension_reason TEXT,
    suspended_by TEXT,
    suspended_at INTEGER,
    suspended_until INTEGER,
    reinstated_at INTEGER,

    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    last_login_at INTEGER,

    last_role_check_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_staff_accounts_access_status
ON staff_accounts(portal_access_status);

CREATE INDEX IF NOT EXISTS idx_staff_accounts_suspension
ON staff_accounts(suspended_until);


-- ------------------------------------------------------------
-- 2. DISCORD ROLE CACHE
-- Stores observed Discord roles for short-lived authorization
-- caching. This table does NOT grant permissions by itself.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_role_cache (
    discord_user_id TEXT NOT NULL,
    discord_role_id TEXT NOT NULL,
    discord_role_name TEXT,

    observed_at INTEGER NOT NULL,

    PRIMARY KEY (discord_user_id, discord_role_id),

    FOREIGN KEY (discord_user_id)
        REFERENCES staff_accounts(discord_user_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_staff_role_cache_observed
ON staff_role_cache(observed_at);


-- ------------------------------------------------------------
-- 3. AUTHENTICATION SESSIONS
-- Only hashes of random session tokens are stored.
-- Never store the browser's raw session token here.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_sessions (
    session_id TEXT PRIMARY KEY,

    discord_user_id TEXT NOT NULL,

    session_token_hash TEXT NOT NULL UNIQUE,
    csrf_token_hash TEXT,

    auth_level TEXT NOT NULL DEFAULT 'standard'
        CHECK (auth_level IN ('standard', 'executive')),

    authenticated_at INTEGER NOT NULL,
    mfa_verified_at INTEGER NOT NULL,

    executive_auth_verified_at INTEGER,

    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    last_activity_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,

    ip_address_hash TEXT,
    user_agent TEXT,

    revoked_at INTEGER,
    revocation_reason TEXT,

    FOREIGN KEY (discord_user_id)
        REFERENCES staff_accounts(discord_user_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_staff_sessions_user
ON staff_sessions(discord_user_id);

CREATE INDEX IF NOT EXISTS idx_staff_sessions_expiration
ON staff_sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_staff_sessions_revoked
ON staff_sessions(revoked_at);


-- ------------------------------------------------------------
-- 4. MULTI-FACTOR AUTHENTICATION METHODS
-- Encrypted values are ciphertext, never plaintext secrets.
-- Encryption keys must be stored as Worker secrets.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_mfa_methods (
    method_id TEXT PRIMARY KEY,

    discord_user_id TEXT NOT NULL,

    method_type TEXT NOT NULL
        CHECK (method_type IN ('totp', 'email')),

    method_label TEXT,

    encrypted_value TEXT NOT NULL,
    encryption_key_version TEXT NOT NULL,

    verified_at INTEGER,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    last_used_at INTEGER,

    disabled_at INTEGER,

    FOREIGN KEY (discord_user_id)
        REFERENCES staff_accounts(discord_user_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_staff_mfa_user
ON staff_mfa_methods(discord_user_id);

CREATE INDEX IF NOT EXISTS idx_staff_mfa_active
ON staff_mfa_methods(discord_user_id, disabled_at);


-- ------------------------------------------------------------
-- 5. MFA RECOVERY CODES
-- Store only cryptographic hashes of one-time recovery codes.
-- A code can only be used once.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_recovery_codes (
    recovery_code_id TEXT PRIMARY KEY,

    discord_user_id TEXT NOT NULL,

    code_hash TEXT NOT NULL,

    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    used_at INTEGER,

    FOREIGN KEY (discord_user_id)
        REFERENCES staff_accounts(discord_user_id)
        ON DELETE CASCADE,

    UNIQUE (discord_user_id, code_hash)
);

CREATE INDEX IF NOT EXISTS idx_staff_recovery_codes_user
ON staff_recovery_codes(discord_user_id, used_at);


-- ------------------------------------------------------------
-- 6. VERIFIED RECOVERY EMAILS
-- Supports the separately verified recovery email.
-- Email addresses must be encrypted by the Worker.
-- Email verification alone never grants account access.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_recovery_emails (
    recovery_email_id TEXT PRIMARY KEY,

    discord_user_id TEXT NOT NULL UNIQUE,

    encrypted_email TEXT NOT NULL,
    email_fingerprint TEXT NOT NULL,

    encryption_key_version TEXT NOT NULL,

    verified_at INTEGER,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),

    disabled_at INTEGER,

    FOREIGN KEY (discord_user_id)
        REFERENCES staff_accounts(discord_user_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_staff_recovery_emails_fingerprint
ON staff_recovery_emails(email_fingerprint);


-- ------------------------------------------------------------
-- 7. PERMISSION PIN CREDENTIALS
-- Only salted password hashes are stored.
-- Never store a PIN in plaintext.
-- Lockout and expiry enforcement happens in the Worker.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_pin_credentials (
    discord_user_id TEXT PRIMARY KEY,

    pin_hash TEXT NOT NULL,
    pin_salt TEXT NOT NULL,

    hash_algorithm TEXT NOT NULL,
    hash_iterations INTEGER NOT NULL,

    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    expires_at INTEGER,

    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until INTEGER,

    last_successful_use_at INTEGER,

    FOREIGN KEY (discord_user_id)
        REFERENCES staff_accounts(discord_user_id)
        ON DELETE CASCADE
);


-- ------------------------------------------------------------
-- 8. AUDIT LOG
-- Append-only records of security and administrative actions.
-- Hash-chain values are calculated by the Worker.
-- Do not store passwords, PINs, tokens, or MFA secrets here.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_log (
    audit_id TEXT PRIMARY KEY,

    actor_discord_user_id TEXT,
    target_discord_user_id TEXT,

    action TEXT NOT NULL,
    category TEXT NOT NULL,

    outcome TEXT NOT NULL
        CHECK (outcome IN (
            'success',
            'failure',
            'rejected',
            'warning'
        )),

    description TEXT,

    metadata_json TEXT NOT NULL DEFAULT '{}'
        CHECK (json_valid(metadata_json)),

    request_id TEXT,

    previous_hash TEXT,
    entry_hash TEXT NOT NULL,

    created_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created
ON audit_log(created_at);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor
ON audit_log(actor_discord_user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_audit_log_target
ON audit_log(target_discord_user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_audit_log_category
ON audit_log(category, created_at);

CREATE INDEX IF NOT EXISTS idx_audit_log_request
ON audit_log(request_id);


-- ------------------------------------------------------------
-- 9. AUDIT LOG IMMUTABILITY
-- Prevent ordinary UPDATE and DELETE operations.
-- New records must be inserted instead.
-- ------------------------------------------------------------

CREATE TRIGGER IF NOT EXISTS prevent_audit_log_update
BEFORE UPDATE ON audit_log
BEGIN
    SELECT RAISE(ABORT, 'Audit log records cannot be updated');
END;

CREATE TRIGGER IF NOT EXISTS prevent_audit_log_delete
BEFORE DELETE ON audit_log
BEGIN
    SELECT RAISE(ABORT, 'Audit log records cannot be deleted');
END;


-- ============================================================
-- END OF MIGRATION 0001
-- ============================================================
