CREATE TABLE IF NOT EXISTS accounts (
    account_id UUID PRIMARY KEY,
    display_name VARCHAR(64) NOT NULL,
    account_type VARCHAR(24) NOT NULL DEFAULT 'guest',
    status VARCHAR(24) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
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

-- 增量迁移兼容已建库：旧对局允许新增元数据为空，保留全部历史行。
ALTER TABLE game_matches ADD COLUMN IF NOT EXISTS room_id TEXT;
ALTER TABLE game_matches ADD COLUMN IF NOT EXISTS winner VARCHAR(24);
ALTER TABLE game_matches ADD COLUMN IF NOT EXISTS result_reason VARCHAR(64);
ALTER TABLE game_matches ADD COLUMN IF NOT EXISTS source VARCHAR(24);
ALTER TABLE game_matches ADD COLUMN IF NOT EXISTS last_sequence BIGINT NOT NULL DEFAULT 0;

-- client_id 是客户端提供的连接标识；没有认证证据时不写 account_id。
CREATE TABLE IF NOT EXISTS game_match_players (
    match_id UUID NOT NULL REFERENCES game_matches(match_id),
    client_id TEXT NOT NULL,
    seat VARCHAR(24) NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY(match_id, seat),
    UNIQUE(match_id, client_id)
);

CREATE INDEX IF NOT EXISTS game_matches_created_at_idx ON game_matches(created_at DESC, match_id DESC);
CREATE INDEX IF NOT EXISTS game_matches_room_id_idx ON game_matches(room_id, created_at DESC);

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
('mahjong', 'guiyang', '1.0.0', '贵阳麻将')
ON CONFLICT (game_id, rule_set_id, rule_version) DO NOTHING;

INSERT INTO feature_flags(flag_key, enabled) VALUES
('ai.bot.enabled', FALSE),
('ai.tutorial.enabled', FALSE),
('ai.hint.enabled', FALSE),
('ai.coach.enabled', FALSE),
('ai.puzzle.enabled', FALSE),
('ai.replay_analysis.enabled', FALSE)
ON CONFLICT (flag_key) DO NOTHING;
