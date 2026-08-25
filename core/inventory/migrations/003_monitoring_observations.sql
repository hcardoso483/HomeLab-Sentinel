PRAGMA foreign_keys = ON;

CREATE TABLE monitoring_observations (
    monitoring_observation_id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    provider TEXT NOT NULL,
    check_type TEXT NOT NULL,
    target TEXT NOT NULL,
    checked_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    status TEXT NOT NULL,
    latency_ms REAL,
    payload_json TEXT NOT NULL,
    payload_hash TEXT NOT NULL UNIQUE,

    FOREIGN KEY (entity_id)
        REFERENCES entities (entity_id)
        ON DELETE RESTRICT,

    CHECK (status IN ('success', 'failed', 'unknown')),
    CHECK (latency_ms IS NULL OR latency_ms >= 0.0),
    CHECK (json_valid(payload_json))
);

CREATE INDEX idx_monitoring_observations_entity_checked
    ON monitoring_observations (entity_id, checked_at);

CREATE INDEX idx_monitoring_observations_status
    ON monitoring_observations (status);

PRAGMA user_version = 3;
