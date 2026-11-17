CREATE TABLE IF NOT EXISTS accounts (
    account_id UUID PRIMARY KEY,
    display_name VARCHAR(64) NOT NULL,
    account_type VARCHAR(24) NOT NULL DEFAULT 'guest',
    status VARCHAR(24) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS accounts_display_name_lookup ON accounts(display_name);

-- Reservations outlive account anonymization and carry no account identity.
CREATE TABLE IF NOT EXISTS guest_default_names (
    display_name VARCHAR(4) PRIMARY KEY CHECK (char_length(display_name) = 4 AND display_name COLLATE "C" ~ '^[一-龥]{4}$')
);

CREATE TABLE IF NOT EXISTS account_sessions (
    token_hash BYTEA PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS account_sessions_account ON account_sessions(account_id);
CREATE INDEX IF NOT EXISTS account_sessions_expiry ON account_sessions(expires_at);

CREATE TABLE IF NOT EXISTS account_password_credentials (
    username VARCHAR(32) PRIMARY KEY CHECK (username COLLATE "C" ~ '^[a-z0-9][a-z0-9_]{2,31}$'),
    account_id UUID NOT NULL UNIQUE REFERENCES accounts(account_id) ON DELETE CASCADE,
    salt BYTEA NOT NULL CHECK (octet_length(salt) = 16),
    password_hash BYTEA NOT NULL CHECK (octet_length(password_hash) = 32),
    scheme TEXT NOT NULL CHECK (scheme = 'argon2id-v1')
);

CREATE TABLE IF NOT EXISTS guest_account_deletion_requests (
    request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL UNIQUE REFERENCES accounts(account_id),
    status VARCHAR(32) NOT NULL DEFAULT 'pending_retention_review' CHECK (status = 'pending_retention_review'),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS identity_bindings (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    provider VARCHAR(32) NOT NULL,
    provider_open_id VARCHAR(128),
    provider_union_id VARCHAR(128),
    provider_app_id VARCHAR(128),
    product_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(provider, provider_open_id, provider_app_id)
);

CREATE TABLE IF NOT EXISTS products (
    product_id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS games (
    game_id VARCHAR(64) PRIMARY KEY,
    game_category VARCHAR(32) NOT NULL,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS rule_sets (
    game_id VARCHAR(64) NOT NULL REFERENCES games(game_id),
    rule_set_id VARCHAR(64) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY(game_id, rule_set_id, rule_version)
);

CREATE TABLE IF NOT EXISTS player_game_profiles (
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    game_id VARCHAR(64) NOT NULL REFERENCES games(game_id),
    level INTEGER NOT NULL DEFAULT 1,
    rating INTEGER NOT NULL DEFAULT 1000,
    games_played INTEGER NOT NULL DEFAULT 0,
    wins INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(account_id, game_id)
);

CREATE TABLE IF NOT EXISTS wallet_accounts (
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    asset_id VARCHAR(64) NOT NULL,
    scope VARCHAR(32) NOT NULL,
    balance BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(account_id, asset_id, scope)
);

CREATE TABLE IF NOT EXISTS wallet_ledger (
    ledger_id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    asset_id VARCHAR(64) NOT NULL,
    scope VARCHAR(32) NOT NULL,
    delta BIGINT NOT NULL,
    reason VARCHAR(64) NOT NULL,
    reference_id VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE wallet_ledger ADD COLUMN IF NOT EXISTS performed_by VARCHAR(128);
ALTER TABLE wallet_ledger ADD COLUMN IF NOT EXISTS target_display_name VARCHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS wallet_guest_welcome_eggs_once
    ON wallet_ledger(account_id, asset_id, scope) WHERE reason = 'guest_welcome_eggs';

CREATE UNIQUE INDEX IF NOT EXISTS wallet_mahjong_settlement_eggs_once
    ON wallet_ledger(reference_id, account_id) WHERE reason = 'mahjong_settlement_eggs';

CREATE TABLE IF NOT EXISTS payment_orders (
    payment_order_id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    product_id VARCHAR(64),
    game_id VARCHAR(64),
    sku_id VARCHAR(64) NOT NULL,
    channel VARCHAR(32) NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency VARCHAR(16) NOT NULL DEFAULT 'CNY',
    status VARCHAR(24) NOT NULL,
    channel_order_id VARCHAR(128),
    idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS game_matches (
    match_id UUID PRIMARY KEY,
    product_id VARCHAR(64) NOT NULL,
    game_id VARCHAR(64) NOT NULL,
    rule_set_id VARCHAR(64) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,
    status VARCHAR(24) NOT NULL,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mahjong_match_results (
    match_id UUID PRIMARY KEY REFERENCES game_matches(match_id),
    public_match_id TEXT UNIQUE NOT NULL,
    room_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('quick', 'friend', 'training')),
    effective_rule JSONB NOT NULL,
    scores INTEGER[] NOT NULL CHECK (cardinality(scores) = 4),
    winners SMALLINT[] NOT NULL,
    win_from SMALLINT NOT NULL CHECK (win_from BETWEEN -1 AND 3),
    win_kind TEXT NOT NULL,
    reason TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mahjong_match_members (
    match_id UUID NOT NULL REFERENCES mahjong_match_results(match_id),
    seat SMALLINT NOT NULL CHECK (seat BETWEEN 0 AND 3),
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    PRIMARY KEY (match_id, seat),
    UNIQUE (match_id, account_id)
);
CREATE INDEX IF NOT EXISTS mahjong_match_members_account ON mahjong_match_members(account_id, match_id);

ALTER TABLE mahjong_match_results ADD COLUMN IF NOT EXISTS score_breakdown JSONB CHECK (jsonb_typeof(score_breakdown) = 'object');
ALTER TABLE mahjong_match_results ADD COLUMN IF NOT EXISTS public_replay JSONB CHECK (jsonb_typeof(public_replay) = 'object');

-- Reportable play can precede game_matches creation at settlement.
CREATE TABLE IF NOT EXISTS mahjong_table_reports (
    match_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    reporter_account_id UUID NOT NULL REFERENCES accounts(account_id),
    target_account_id UUID NOT NULL REFERENCES accounts(account_id),
    reporter_seat SMALLINT NOT NULL CHECK (reporter_seat BETWEEN 0 AND 3),
    target_seat SMALLINT NOT NULL CHECK (target_seat BETWEEN 0 AND 3),
    reason TEXT NOT NULL CHECK (reason IN ('abusive_chat', 'spam', 'voice_abuse', 'other')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CHECK (reporter_account_id <> target_account_id AND reporter_seat <> target_seat),
    PRIMARY KEY (match_id, reporter_account_id, target_account_id)
);
CREATE INDEX IF NOT EXISTS mahjong_table_reports_recent ON mahjong_table_reports(created_at DESC);

ALTER TABLE mahjong_table_reports ADD COLUMN IF NOT EXISTS report_id UUID NOT NULL DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS mahjong_table_reports_id ON mahjong_table_reports(report_id);

-- An absent disposition is pending. A report can have only one final disposition.
CREATE TABLE IF NOT EXISTS mahjong_table_report_reviews (
    report_id UUID PRIMARY KEY REFERENCES mahjong_table_reports(report_id),
    status_before TEXT NOT NULL CHECK (status_before = 'pending'),
    status_after TEXT NOT NULL CHECK (status_after IN ('dismissed', 'upheld')),
    analyst TEXT NOT NULL CHECK (char_length(analyst) BETWEEN 1 AND 128),
    note_before TEXT NOT NULL CHECK (char_length(note_before) <= 240),
    note_after TEXT NOT NULL CHECK (char_length(note_after) <= 240),
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- Private recovery data. Public history and administrative match queries use
-- their own tables and never read this payload.
CREATE TABLE IF NOT EXISTS mahjong_active_matches (
    match_id TEXT PRIMARY KEY,
    room_id TEXT UNIQUE NOT NULL,
    revision BIGINT NOT NULL CHECK (revision > 0),
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object')
);

-- Existing checkpoints retain their application-side deadline until the next write.
ALTER TABLE mahjong_active_matches ADD COLUMN IF NOT EXISTS committed_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS mahjong_active_completions (
    match_id TEXT PRIMARY KEY,
    revision BIGINT NOT NULL CHECK (revision > 0)
);

-- Old receipts cannot prove which settlement won. Keep them for the
-- insert fence, and accept exact replays only when a fingerprint exists.
ALTER TABLE mahjong_active_completions ADD COLUMN IF NOT EXISTS fingerprint BYTEA CHECK (octet_length(fingerprint) = 32);

CREATE TABLE IF NOT EXISTS mahjong_friend_rooms (
    room_id TEXT PRIMARY KEY,
    generation BIGINT NOT NULL CHECK (generation > 0),
    revision BIGINT NOT NULL CHECK (revision > 0),
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE IF NOT EXISTS mahjong_room_admission_operations (
    request_id UUID PRIMARY KEY,
    room_id TEXT NOT NULL,
    generation BIGINT NOT NULL CHECK (generation > 0),
    admission_revision BIGINT NOT NULL CHECK (admission_revision > 0),
    paused BOOLEAN NOT NULL,
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 160),
    admin_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (room_id, generation, admission_revision)
);

CREATE TABLE IF NOT EXISTS game_events (
    match_id UUID NOT NULL REFERENCES game_matches(match_id),
    sequence BIGINT NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(match_id, sequence)
);

CREATE TABLE IF NOT EXISTS game_snapshots (
    match_id UUID NOT NULL REFERENCES game_matches(match_id),
    sequence BIGINT NOT NULL,
    snapshot JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(match_id, sequence)
);

CREATE TABLE IF NOT EXISTS feature_flags (
    flag_key VARCHAR(128) PRIMARY KEY,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    product_id VARCHAR(64),
    game_id VARCHAR(64),
    rule_set_id VARCHAR(64),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO products(product_id, name) VALUES
('xbd_chinese_chess', '小板凳象棋'),
('xbd_mahjong', '小板凳麻将')
ON CONFLICT (product_id) DO NOTHING;

INSERT INTO games(game_id, game_category, name) VALUES
('chinese_chess', 'board', '中国象棋'),
('mahjong', 'tile', '麻将')
ON CONFLICT (game_id) DO NOTHING;

INSERT INTO rule_sets(game_id, rule_set_id, rule_version, name) VALUES
('chinese_chess', 'standard', '1.0.0', '中国象棋标准规则'),
('mahjong', 'guiyang', '1.0.0', '贵阳麻将'),
('mahjong', 'guiyang', '2.0.0', '贵阳捉鸡'),
('mahjong', 'basic_108', '1.0.0', '基础 108')
ON CONFLICT (game_id, rule_set_id, rule_version) DO NOTHING;

INSERT INTO feature_flags(flag_key, enabled) VALUES
('ai.bot.enabled', FALSE),
('ai.tutorial.enabled', FALSE),
('ai.hint.enabled', FALSE),
('ai.coach.enabled', FALSE),
('ai.puzzle.enabled', FALSE),
('ai.replay_analysis.enabled', FALSE)
ON CONFLICT (flag_key) DO NOTHING;
