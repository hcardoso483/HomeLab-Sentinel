#!/usr/bin/env python3

import argparse
import json
import os
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[2]

if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from core.identity.identity import lookup as lookup_identity
from core.identity.identity import open_db as open_identity_db
from core.identity.identity import register as register_identity

DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
DEFAULT_IDENTITY_DATABASE = Path(
    os.environ.get(
        "IDENTITY_DATABASE",
        "/srv/homelab-sentinel/sentinel/identity.db",
    )
)

GLOBAL_MAC_CONFIDENCE = 0.90
LOCAL_MAC_CONFIDENCE = 0.60
IP_HISTORY_CONFIDENCE = 0.40


def info(message):
    print(f"[INFO] {message}", file=sys.stderr)


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def pending_observations(connection):
    return connection.execute("""
        SELECT
            o.observation_id,
            o.payload_json
        FROM observations o
        JOIN correlation_state c
          ON c.observation_id = o.observation_id
        WHERE c.status = 'pending'
        ORDER BY o.received_at, o.observation_id
    """).fetchall()


def entities_for_mac(connection, mac_address):
    rows = connection.execute("""
        SELECT DISTINCT eo.entity_id
        FROM entity_observations eo
        JOIN observations o
          ON o.observation_id = eo.observation_id
        WHERE json_extract(o.payload_json, '$.mac_address') = ?
        ORDER BY eo.entity_id
    """, (mac_address,)).fetchall()

    return [row[0] for row in rows]


def entities_for_ip(connection, ip_address):
    rows = connection.execute("""
        SELECT DISTINCT eo.entity_id
        FROM entity_observations eo
        JOIN observations o
          ON o.observation_id = eo.observation_id
        WHERE EXISTS (
            SELECT 1
            FROM json_each(o.payload_json, '$.ip_addresses')
            WHERE json_each.value = ?
        )
        ORDER BY eo.entity_id
    """, (ip_address,)).fetchall()

    return [row[0] for row in rows]


def entity_has_strong_mac_history(connection, entity_id):
    row = connection.execute("""
        SELECT COUNT(*)
        FROM entity_observations eo
        JOIN observations o
          ON o.observation_id = eo.observation_id
        WHERE eo.entity_id = ?
          AND json_extract(o.payload_json, '$.mac_address') IS NOT NULL
    """, (entity_id,)).fetchone()

    return row[0] > 0


def mac_is_locally_administered(mac_address):
    first_octet = int(mac_address.split(":", 1)[0], 16)
    return bool(first_octet & 0x02)


def create_entity(connection, entity_id=None):
    if entity_id is None:
        entity_id = f"dev-{uuid.uuid4().hex}"

    now = utc_now()

    connection.execute("""
        INSERT INTO entities (
            entity_id,
            entity_type,
            created_at,
            updated_at
        )
        VALUES (?, 'device', ?, ?)
    """, (entity_id, now, now))

    return entity_id


def resolve_observation(connection, observation_id, entity_id,
                        method, confidence):
    now = utc_now()

    connection.execute("""
        INSERT INTO entity_observations (
            entity_id,
            observation_id,
            correlated_at,
            correlation_method
        )
        VALUES (?, ?, ?, ?)
    """, (entity_id, observation_id, now, method))

    connection.execute("""
        UPDATE correlation_state
        SET
            status='resolved',
            entity_id=?,
            correlation_method=?,
            confidence=?,
            reason=NULL,
            decided_at=?
        WHERE observation_id=?
    """, (entity_id, method, confidence, now, observation_id))

    connection.execute("""
        UPDATE entities
        SET updated_at=?
        WHERE entity_id=?
    """, (now, entity_id))


def mark_unresolved(connection, observation_id, reason):
    connection.execute("""
        UPDATE correlation_state
        SET
            status='unresolved',
            entity_id=NULL,
            correlation_method=NULL,
            confidence=NULL,
            reason=?,
            decided_at=?
        WHERE observation_id=?
    """, (reason, utc_now(), observation_id))


def correlate_observation(
        connection,
        identity_connection,
        observation_id,
        payload_json):
    record = json.loads(payload_json)

    mac_address = record.get("mac_address")

    # ------------------------------------------------------------------
    # PRIMARY IDENTITY: MAC ADDRESS
    # ------------------------------------------------------------------
    if mac_address is not None:
        matches = entities_for_mac(connection, mac_address)
        local_mac = mac_is_locally_administered(mac_address)

        if local_mac:
            new_method = "new-entity-local-mac-evidence"
            match_method = "local-mac-history-match"
            confidence = LOCAL_MAC_CONFIDENCE
        else:
            new_method = "new-entity-mac-evidence"
            match_method = "mac-history-match"
            confidence = GLOBAL_MAC_CONFIDENCE

        if len(matches) == 0:
            if not local_mac:
                persistent_identity = lookup_identity(
                    identity_connection,
                    mac_address,
                )

                if persistent_identity is not None:
                    entity_id = create_entity(
                        connection,
                        persistent_identity["entity_id"],
                    )

                    resolve_observation(
                        connection,
                        observation_id,
                        entity_id,
                        "persistent-identity-mac-match",
                        persistent_identity["confidence"],
                    )

                    register_identity(
                        identity_connection,
                        entity_id,
                        mac_address,
                        record.get("discovered_at") or utc_now(),
                    )

                    return "resolved", entity_id

            entity_id = create_entity(connection)

            resolve_observation(
                connection,
                observation_id,
                entity_id,
                new_method,
                confidence,
            )

            if not local_mac:
                register_identity(
                    identity_connection,
                    entity_id,
                    mac_address,
                    record.get("discovered_at") or utc_now(),
                )

            return "new", entity_id

        if len(matches) == 1:
            entity_id = matches[0]
            resolve_observation(
                connection,
                observation_id,
                entity_id,
                match_method,
                confidence,
            )

            if not local_mac:
                register_identity(
                    identity_connection,
                    entity_id,
                    mac_address,
                    record.get("discovered_at") or utc_now(),
                )

            return "resolved", entity_id

        mark_unresolved(
            connection,
            observation_id,
            "multiple entities share matching MAC evidence",
        )
        return "unresolved", None

    # ------------------------------------------------------------------
    # SECONDARY IDENTITY: HISTORICAL IP (LOW CONFIDENCE)
    # ------------------------------------------------------------------
    ip_addresses = record.get("ip_addresses") or []

    if len(ip_addresses) == 1:
        ip = ip_addresses[0]
        matches = entities_for_ip(connection, ip)

        if len(matches) == 1:
            entity_id = matches[0]

            if entity_has_strong_mac_history(connection, entity_id):
                resolve_observation(
                    connection,
                    observation_id,
                    entity_id,
                    "ip-history-match",
                    IP_HISTORY_CONFIDENCE,
                )
                return "resolved", entity_id

        elif len(matches) > 1:
            mark_unresolved(
                connection,
                observation_id,
                "historical IP matches multiple entities",
            )
            return "unresolved", None

    mark_unresolved(
        connection,
        observation_id,
        "no strong identity evidence available",
    )
    return "unresolved", None


def run_correlation(connection, identity_connection):
    pending = pending_observations(connection)

    created = resolved = unresolved = 0

    for observation_id, payload_json in pending:
        result, entity_id = correlate_observation(
            connection,
            identity_connection,
            observation_id,
            payload_json,
        )

        if result == "new":
            created += 1
            info(f"{observation_id}: created entity {entity_id}")
        elif result == "resolved":
            resolved += 1
            info(f"{observation_id}: linked to entity {entity_id}")
        else:
            unresolved += 1
            info(f"{observation_id}: left unresolved")

    connection.commit()

    return len(pending), created, resolved, unresolved


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Correlation Engine"
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )

    parser.add_argument(
        "--identity-database",
        type=Path,
        default=DEFAULT_IDENTITY_DATABASE,
        help=(
            "Persistent Identity SQLite database path "
            f"(default: {DEFAULT_IDENTITY_DATABASE})"
        ),
    )

    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        connection = sqlite3.connect(args.database)

        try:
            connection.execute("PRAGMA foreign_keys = ON")

            version = connection.execute(
                "PRAGMA user_version"
            ).fetchone()[0]

            if version < 2:
                raise ValueError(
                    f"inventory schema version {version} "
                    "does not support correlation"
                )

            identity_connection = open_identity_db(
                args.identity_database,
                create=True,
            )

            try:
                total, created, resolved, unresolved = run_correlation(
                    connection,
                    identity_connection,
                )
            finally:
                identity_connection.close()

        finally:
            connection.close()

    except (sqlite3.Error, ValueError, json.JSONDecodeError) as exc:
        error(f"Correlation failed: {exc}")
        return 1

    info(
        "Correlation complete. "
        f"Processed: {total}, "
        f"created: {created}, "
        f"resolved: {resolved}, "
        f"unresolved: {unresolved}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
