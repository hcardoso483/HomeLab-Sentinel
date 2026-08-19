PRAGMA foreign_keys = ON;

CREATE TABLE correlation_state (
    observation_id TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'pending',
    entity_id TEXT,
    correlation_method TEXT,
    confidence REAL,
    reason TEXT,
    decided_at TEXT,

    FOREIGN KEY (observation_id)
        REFERENCES observations (observation_id)
        ON DELETE RESTRICT,

    FOREIGN KEY (entity_id)
        REFERENCES entities (entity_id)
        ON DELETE RESTRICT,

    CHECK (status IN ('pending', 'resolved', 'unresolved')),
    CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0))
);

INSERT INTO correlation_state (observation_id, status)
SELECT observation_id, 'pending'
FROM observations
WHERE observation_id NOT IN (
    SELECT observation_id FROM correlation_state
);

CREATE TRIGGER correlation_state_pending_insert
AFTER INSERT ON observations
BEGIN
    INSERT INTO correlation_state (
        observation_id,
        status
    )
    VALUES (
        NEW.observation_id,
        'pending'
    );
END;

CREATE INDEX idx_correlation_state_status
    ON correlation_state (status);

CREATE INDEX idx_correlation_state_entity
    ON correlation_state (entity_id);

PRAGMA user_version = 2;
