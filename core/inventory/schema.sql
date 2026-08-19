PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS observations (
    observation_id TEXT PRIMARY KEY,
    schema_version TEXT NOT NULL,
    provider TEXT NOT NULL,
    discovery_method TEXT NOT NULL,
    discovered_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    payload_hash TEXT NOT NULL UNIQUE,
    CHECK (json_valid(payload_json))
);

CREATE INDEX IF NOT EXISTS idx_observations_discovered_at
    ON observations (discovered_at);

CREATE INDEX IF NOT EXISTS idx_observations_provider
    ON observations (provider);

CREATE TABLE IF NOT EXISTS entities (
    entity_id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL DEFAULT 'device',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS entity_observations (
    entity_id TEXT NOT NULL,
    observation_id TEXT NOT NULL,
    correlated_at TEXT NOT NULL,
    correlation_method TEXT,

    PRIMARY KEY (entity_id, observation_id),

    FOREIGN KEY (entity_id)
        REFERENCES entities (entity_id)
        ON DELETE CASCADE,

    FOREIGN KEY (observation_id)
        REFERENCES observations (observation_id)
        ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_entity_observations_observation
    ON entity_observations (observation_id);

CREATE TRIGGER IF NOT EXISTS observations_immutable_update
BEFORE UPDATE ON observations
BEGIN
    SELECT RAISE(ABORT, 'observations are immutable');
END;

CREATE TRIGGER IF NOT EXISTS observations_immutable_delete
BEFORE DELETE ON observations
BEGIN
    SELECT RAISE(ABORT, 'observations are immutable');
END;

PRAGMA user_version = 1;
