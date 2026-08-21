#!/usr/bin/env python3

import argparse
import sqlite3
import subprocess
import sys
from pathlib import Path


DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")


def log(level, message):
    print(f"[{level}] {message}")


def verify_database(database):
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    except sqlite3.Error as exc:
        log("FAIL", f"Unable to open inventory database: {exc}")
        return False

    try:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    except sqlite3.Error as exc:
        log("FAIL", f"Unable to verify inventory database: {exc}")
        return False
    finally:
        connection.close()

    if version < 2:
        log("FAIL", f"Unsupported inventory schema version: {version}")
        return False

    if integrity != "ok":
        log("FAIL", f"SQLite integrity_check failed: {integrity}")
        return False

    log("PASS", f"Inventory schema supported: version {version}")
    log("PASS", "SQLite integrity_check = ok")
    return True


def initialize_database(app_root, database):
    store = app_root / "core" / "inventory" / "store.py"

    if not store.is_file():
        log("FAIL", f"Inventory store not found: {store}")
        return False

    log("INFO", f"Initializing inventory database: {database}")

    result = subprocess.run(
        [
            str(store),
            "--database",
            str(database),
        ],
        stdin=subprocess.DEVNULL,
    )

    if result.returncode != 0:
        log("FAIL", "Inventory initialization failed.")
        return False

    if not database.is_file():
        log("FAIL", "Inventory initialization completed but database is missing.")
        return False

    log("PASS", "Inventory database initialized.")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel inventory state manager"
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"Inventory database path (default: {DEFAULT_DATABASE})",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    app_root = script_dir.parent
    database = args.database

    if database.exists():
        log("PASS", f"Inventory database exists: {database}")
    else:
        log("RECOVER", f"Inventory database missing: {database}")

        if not initialize_database(app_root, database):
            return 1

    if not verify_database(database):
        return 1

    log("PASS", "Inventory state is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
