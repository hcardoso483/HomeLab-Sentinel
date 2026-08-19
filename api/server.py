#!/usr/bin/env python3

import argparse
import json
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from core.inventory.inventory import (
    DEFAULT_DATABASE,
    current_schema_version,
    history_records,
    inventory_record,
    inventory_records,
    unresolved_records,
)


def json_bytes(payload):
    return json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")


class CoreAPIHandler(BaseHTTPRequestHandler):
    database_path = DEFAULT_DATABASE

    def log_message(self, format, *args):
        print(f"[API] {self.address_string()} { format % args}", file=sys.stderr)

    def send_json(self, status, payload):
        body = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_api_error(self, status, code, message):
        self.send_json(status, {"error": {"code": code, "message": message}})

    def open_database(self):
        if not Path(self.database_path).is_file():
            raise FileNotFoundError(self.database_path)
        return sqlite3.connect(self.database_path)

    def method_not_allowed(self):
        self.send_api_error(405, "method_not_allowed", "HTTP method is not allowed for this resource.")

    do_POST = method_not_allowed
    do_PUT = method_not_allowed
    do_PATCH = method_not_allowed
    do_DELETE = method_not_allowed

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        try:
            if path == "/api/v1/health":
                with self.open_database() as connection:
                    version = current_schema_version(connection)
                self.send_json(200, {"status": "ok", "inventory_schema_version": version})
                return

            if path == "/api/v1/inventory":
                with self.open_database() as connection:
                    items = inventory_records(connection)
                self.send_json(200, {"items": items})
                return

            if path == "/api/v1/inventory/unresolved":
                with self.open_database() as connection:
                    items = unresolved_records(connection)
                self.send_json(200, {"items": items})
                return

            prefix = "/api/v1/inventory/"
            if path.startswith(prefix):
                rest = path[len(prefix):]
                if not rest:
                    self.send_api_error(404, "not_found", "Requested Core resource does not exist.")
                    return

                if rest.endswith("/history"):
                    entity_id = rest[:-len("/history")]
                    if not entity_id:
                        self.send_api_error(400, "invalid_request", "Missing Sentinel entity ID.")
                        return
                    with self.open_database() as connection:
                        items = history_records(connection, entity_id)
                    self.send_json(200, {"entity_id": entity_id, "items": items})
                    return

                entity_id = rest
                with self.open_database() as connection:
                    record = inventory_record(connection, entity_id)
                self.send_json(200, record)
                return

            self.send_api_error(404, "not_found", "Requested Core resource does not exist.")

        except FileNotFoundError:
            self.send_api_error(500, "inventory_database_unavailable", "Inventory database is not available.")
        except ValueError as exc:
            if str(exc).startswith("entity not found: "):
                self.send_api_error(404, "entity_not_found", "Sentinel entity not found.")
            else:
                self.send_api_error(500, "core_dependency_failed", "Required Core dependency failed.")
        except (sqlite3.Error, json.JSONDecodeError):
            self.send_api_error(500, "core_dependency_failed", "Required Core dependency failed.")


def main():
    parser = argparse.ArgumentParser(description="HomeLab Sentinel Core API v1.0")
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8000, help="Bind port (default: 8000)")
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE, help=f"SQLite database path (default: {DEFAULT_DATABASE})")
    args = parser.parse_args()

    handler = CoreAPIHandler
    handler.database_path = args.database

    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[INFO] Core API listening on http://{args.host}:{args.port}", file=sys.stderr)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
