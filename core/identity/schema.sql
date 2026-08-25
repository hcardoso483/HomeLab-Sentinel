PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS identities (
    identity_type TEXT NOT NULL,
    identity_value TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    identity_class TEXT NOT NULL,
    confidence REAL NOT NULL,
    authoritative INTEGER NOT NULL,
    first_seen TEXT NOT NULL,
    last_confirmed TEXT NOT NULL,
    PRIMARY KEY (identity_type, identity_value),
    CHECK (identity_type = 'mac'),
    CHECK (identity_class IN ('global-mac', 'local-mac')),
    CHECK (confidence >= 0.0 AND confidence <= 1.0),
    CHECK (authoritative IN (0, 1))
);

CREATE INDEX IF NOT EXISTS idx_identities_entity
    ON identities (entity_id);

CREATE INDEX IF NOT EXISTS idx_identities_authoritative
    ON identities (identity_type, authoritative);

PRAGMA user_version = 1;
