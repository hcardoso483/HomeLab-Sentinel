#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
import time
from collections import OrderedDict


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def observation_key(record):
    """
    Produce a cycle-local key for repeated observations.

    v1 preference:
      1. MAC address when available.
      2. Otherwise the observed IP set + hostname.

    This key is ONLY for consolidating repeated observations inside one
    discovery cycle. It is not Persistent Identity.
    """
    mac = record.get("mac_address")

    if mac:
        return ("mac", mac)

    ip_addresses = tuple(sorted(record.get("ip_addresses") or []))
    hostname = record.get("hostname")

    return ("weak", ip_addresses, hostname)


def run_provider(provider, target):
    result = subprocess.run(
        [provider, target],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if result.returncode != 0:
        if result.stderr.strip():
            print(result.stderr.rstrip(), file=sys.stderr)

        raise RuntimeError(
            f"Discovery provider failed with exit {result.returncode}"
        )

    records = []

    for line_number, line in enumerate(
        result.stdout.splitlines(),
        start=1,
    ):
        line = line.strip()

        if not line:
            continue

        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(
                f"Provider output line {line_number} is invalid JSON: {exc}"
            ) from exc

        if not isinstance(record, dict):
            raise ValueError(
                f"Provider output line {line_number} must be a JSON object"
            )

        records.append(record)

    return records


def consolidate(pass_records, passes_total):
    """
    Consolidate observations while preserving pass evidence.

    The most recent observation payload becomes the representative record.
    Presence evidence remains explicit through passes_observed,
    passes_total, and observed_passes.
    """
    combined = OrderedDict()

    for pass_number, records in enumerate(pass_records, start=1):
        seen_this_pass = set()

        for record in records:
            key = observation_key(record)

            # A provider should not gain extra presence credit by emitting
            # the same logical host more than once in one pass.
            if key in seen_this_pass:
                continue

            seen_this_pass.add(key)

            if key not in combined:
                combined[key] = {
                    "record": dict(record),
                    "passes": [],
                }
            else:
                # Keep the newest provider representation while retaining
                # evidence accumulated from previous passes.
                combined[key]["record"] = dict(record)

            combined[key]["passes"].append(pass_number)

    output = []

    for item in combined.values():
        record = dict(item["record"])
        observed_passes = item["passes"]

        record["passes_observed"] = len(observed_passes)
        record["passes_total"] = passes_total
        record["observed_passes"] = observed_passes

        output.append(record)

    return output


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Multi-Pass Discovery engine"
    )

    parser.add_argument(
        "--provider",
        required=True,
        help="Single-pass Discovery provider executable",
    )

    parser.add_argument(
        "--target",
        required=True,
        help="Authorized Discovery target passed to the provider",
    )

    parser.add_argument(
        "--passes",
        type=int,
        default=3,
        help="Normal observation passes per cycle (default: 3)",
    )

    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="Seconds between normal passes (default: 2.0)",
    )

    args = parser.parse_args()

    if args.passes < 1:
        error("--passes must be at least 1")
        return 2

    if args.interval < 0:
        error("--interval must not be negative")
        return 2

    pass_records = []

    try:
        for pass_number in range(1, args.passes + 1):
            print(
                f"[INFO] Discovery pass "
                f"{pass_number}/{args.passes}",
                file=sys.stderr,
            )

            records = run_provider(
                args.provider,
                args.target,
            )

            pass_records.append(records)

            print(
                f"[INFO] Discovery pass "
                f"{pass_number}/{args.passes} observations: "
                f"{len(records)}",
                file=sys.stderr,
            )

            if pass_number < args.passes and args.interval > 0:
                time.sleep(args.interval)

        records = consolidate(
            pass_records,
            args.passes,
        )

        for record in records:
            print(
                json.dumps(
                    record,
                    separators=(",", ":"),
                    sort_keys=True,
                )
            )

        print(
            f"[INFO] Multi-Pass Discovery complete. "
            f"Passes: {args.passes}, "
            f"consolidated observations: {len(records)}",
            file=sys.stderr,
        )

        return 0

    except (OSError, RuntimeError, ValueError) as exc:
        error(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
