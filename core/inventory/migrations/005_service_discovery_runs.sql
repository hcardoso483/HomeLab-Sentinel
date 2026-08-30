PRAGMA foreign_keys = ON;

CREATE TABLE service_discovery_runs (
    service_discovery_run_id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    address TEXT NOT NULL,
    provider TEXT NOT NULL,
    started_at TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    outcome TEXT NOT NULL,
    detail TEXT,
    FOREIGN KEY (entity_id)
        REFERENCES entities (entity_id)
        ON DELETE RESTRICT,
    CHECK (length(trim(address)) > 0),
    CHECK (length(trim(provider)) > 0),
    CHECK (outcome IN (
        'success',
        'provider_error',
        'invalid_evidence',
        'store_error'
    )),
    CHECK (detail IS NULL OR length(trim(detail)) > 0)
);

CREATE INDEX idx_service_discovery_runs_target_completed
    ON service_discovery_runs (
        entity_id,
        address,
        completed_at
    );

CREATE INDEX idx_service_discovery_runs_outcome_completed
    ON service_discovery_runs (
        outcome,
        completed_at
    );

CREATE TABLE service_discovery_run_observations (
    service_discovery_run_id TEXT NOT NULL,
    service_observation_id TEXT NOT NULL,
    PRIMARY KEY (
        service_discovery_run_id,
        service_observation_id
    ),
    FOREIGN KEY (service_discovery_run_id)
        REFERENCES service_discovery_runs (service_discovery_run_id)
        ON DELETE RESTRICT,
    FOREIGN KEY (service_observation_id)
        REFERENCES service_observations (service_observation_id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_service_discovery_run_observations_observation
    ON service_discovery_run_observations (
        service_observation_id
    );

PRAGMA user_version = 5;
