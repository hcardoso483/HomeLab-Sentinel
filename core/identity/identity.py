#!/usr/bin/env python3
import argparse, json, re, sqlite3, sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DATABASE = Path('/srv/homelab-sentinel/sentinel/identity.db')
SCHEMA_FILE = Path(__file__).resolve().with_name('schema.sql')
MAC_RE = re.compile(r'^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$')


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def normalize_mac(value):
    mac = value.strip().upper().replace('-', ':')
    if not MAC_RE.fullmatch(mac):
        raise ValueError('invalid MAC address')
    return mac


def classify_mac(mac):
    local = bool(int(mac.split(':', 1)[0], 16) & 0x02)
    return ('local-mac', 0.60, 0) if local else ('global-mac', 0.90, 1)


def validate_entity_id(value):
    if not re.fullmatch(r'dev-[0-9a-f]{32}', value):
        raise ValueError('invalid canonical entity_id')


def initialize(connection):
    version = connection.execute('PRAGMA user_version').fetchone()[0]
    if version == 0:
        connection.executescript(SCHEMA_FILE.read_text(encoding='utf-8'))
        version = connection.execute('PRAGMA user_version').fetchone()[0]
    if version != 1:
        raise ValueError(f'unsupported Persistent Identity schema version: {version}')


def open_db(path, create):
    if not create and not path.is_file():
        raise FileNotFoundError(f'identity database not found: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    initialize(con)
    return con


def register(con, entity_id, mac, seen_at):
    validate_entity_id(entity_id)
    mac = normalize_mac(mac)
    identity_class, confidence, authoritative = classify_mac(mac)
    row = con.execute("SELECT entity_id FROM identities WHERE identity_type='mac' AND identity_value=?", (mac,)).fetchone()
    if row is None:
        con.execute("""
            INSERT INTO identities
            (identity_type, identity_value, entity_id, identity_class, confidence,
             authoritative, first_seen, last_confirmed)
            VALUES ('mac', ?, ?, ?, ?, ?, ?, ?)
        """, (mac, entity_id, identity_class, confidence, authoritative, seen_at, seen_at))
        con.commit()
        return 'created'
    if row[0] != entity_id:
        raise ValueError(f'identity conflict: {mac} already belongs to {row[0]}')
    con.execute("UPDATE identities SET last_confirmed=? WHERE identity_type='mac' AND identity_value=?", (seen_at, mac))
    con.commit()
    return 'confirmed'


def lookup(con, mac, include_non_authoritative=False):
    mac = normalize_mac(mac)
    row = con.execute("""
        SELECT entity_id, identity_class, confidence, authoritative, first_seen, last_confirmed
        FROM identities WHERE identity_type='mac' AND identity_value=?
    """, (mac,)).fetchone()
    if row is None or (not include_non_authoritative and row[3] != 1):
        return None
    return {
        'schema_version': '1.0',
        'entity_id': row[0], 'identity_type': 'mac', 'identity_value': mac,
        'identity_class': row[1], 'confidence': row[2], 'authoritative': bool(row[3]),
        'first_seen': row[4], 'last_confirmed': row[5],
    }


def main():
    p = argparse.ArgumentParser(description='HomeLab Sentinel Persistent Identity v1')
    p.add_argument('--database', type=Path, default=DEFAULT_DATABASE)
    s = p.add_subparsers(dest='cmd', required=True)
    s.add_parser('init')
    r = s.add_parser('register'); r.add_argument('--entity-id', required=True); r.add_argument('--mac', required=True); r.add_argument('--seen-at')
    l = s.add_parser('lookup'); l.add_argument('--mac', required=True); l.add_argument('--include-non-authoritative', action='store_true'); l.add_argument('--json', action='store_true')
    a = p.parse_args()
    try:
        con = open_db(a.database, a.cmd == 'init')
        try:
            if a.cmd == 'init':
                print(f'[PASS] Persistent Identity database ready: {a.database}')
                return 0
            if a.cmd == 'register':
                result = register(con, a.entity_id, a.mac, a.seen_at or utc_now())
                print(f'[PASS] Persistent Identity {result}')
                return 0
            result = lookup(con, a.mac, a.include_non_authoritative)
            if result is None:
                return 1
            print(json.dumps(result, separators=(',', ':'), sort_keys=True) if a.json else result['entity_id'])
            return 0
        finally:
            con.close()
    except (OSError, sqlite3.Error, ValueError) as exc:
        print(f'[ERROR] {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
