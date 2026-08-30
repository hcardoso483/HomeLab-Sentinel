PRAGMA foreign_keys = ON;

CREATE TABLE service_observations (
    service_observation_id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    provider TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    address TEXT NOT NULL,
    protocol TEXT NOT NULL,
    port INTEGER NOT NULL,
    state TEXT NOT NULL,
    service TEXT,
    payload_json TEXT NOT NULL,
    payload_hash TEXT NOT NULL UNIQUE,
    FOREIGN KEY (entity_id)
        REFERENCES entities (entity_id)
        ON DELETE RESTRICT,
    CHECK (protocol IN ('tcp')),
    CHECK (port >= 1 AND port <= 65535),
    CHECK (state IN ('open')),
    CHECK (service IS NULL OR length(trim(service)) > 0),
    CHECK (json_valid(payload_json))
);

CREATE INDEX idx_service_observations_entity_observed
    ON service_observations (entity_id, observed_at);

CREATE INDEX idx_service_observations_endpoint_observed
    ON service_observations (
        entity_id,
        address,
        protocol,
        port,
        observed_at
    );

PRAGMA user_version = 4;
