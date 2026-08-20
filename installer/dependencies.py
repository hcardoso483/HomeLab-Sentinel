#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Dependency:
    name: str
    package: str
    kind: str
    target: str


SUPPORTED_OS_ID = "debian"
SUPPORTED_VERSION_ID = "13"

DEPENDENCIES = (
    Dependency("python3", "python3", "command", "python3"),
    Dependency("curl", "curl", "command", "curl"),
    Dependency("python-yaml", "python3-yaml", "python_import", "yaml"),
    Dependency("python-sqlite3", "libpython3.13-stdlib", "python_import", "sqlite3"),
)


def log(level, message):
    print(f"[{level}] {message}")


def load_os_release():
    data = {}

    with open("/etc/os-release", "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or "=" not in line:
                continue

            key, value = line.split("=", 1)
            data[key] = value.strip().strip('"')

    return data


def validate_host():
    try:
        release = load_os_release()
    except OSError as exc:
        log("FAIL", f"Unable to read /etc/os-release: {exc}")
        return False

    os_id = release.get("ID")
    version_id = release.get("VERSION_ID")

    if os_id != SUPPORTED_OS_ID or version_id != SUPPORTED_VERSION_ID:
        log(
            "FAIL",
            "Unsupported host: "
            f"ID={os_id or 'unknown'} VERSION_ID={version_id or 'unknown'}",
        )
        log(
            "DETAIL",
            f"Supported host: {SUPPORTED_OS_ID} {SUPPORTED_VERSION_ID}",
        )
        return False

    log("PASS", f"Supported host detected: Debian {version_id}")
    return True


def capability_available(
    dependency,
    simulated_missing=None,
    allow_simulation=True,
):
    if allow_simulation and simulated_missing == dependency.name:
        return False

    if dependency.kind == "command":
        return shutil.which(dependency.target) is not None

    if dependency.kind == "python_import":
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                f"import {dependency.target}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0

    raise ValueError(f"Unsupported dependency kind: {dependency.kind}")


def missing_dependencies(simulated_missing=None):
    missing = []

    for dependency in DEPENDENCIES:
        if capability_available(
            dependency,
            simulated_missing=simulated_missing,
        ):
            log("PASS", f"Dependency available: {dependency.name}")
        else:
            log(
                "RECOVER",
                f"Dependency missing: {dependency.name} "
                f"(package: {dependency.package})",
            )
            missing.append(dependency)

    return missing


def install_packages(dependencies):
    packages = list(dict.fromkeys(item.package for item in dependencies))

    if not packages:
        return True

    if os.geteuid() != 0:
        log("FAIL", "Dependency recovery requires root privileges.")
        return False

    apt_get = shutil.which("apt-get")
    if not apt_get:
        log("FAIL", "apt-get is not available on the supported host.")
        return False

    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["APT_LISTCHANGES_FRONTEND"] = "none"

    log("INFO", "Updating package metadata...")

    if subprocess.run([apt_get, "update"], env=env).returncode != 0:
        log("FAIL", "apt-get update failed.")
        return False

    log("INFO", "Installing mandatory Sentinel package(s): " + ", ".join(packages))

    if subprocess.run([apt_get, "install", "-y", *packages], env=env).returncode != 0:
        log("FAIL", "Mandatory dependency installation failed.")
        return False

    return True


def verify_recovery(dependencies):
    failed = False

    for dependency in dependencies:
        if capability_available(
            dependency,
            simulated_missing=None,
            allow_simulation=False,
        ):
            log("PASS", f"Dependency recovered and verified: {dependency.name}")
        else:
            log("FAIL", f"Dependency recovery failed: {dependency.name}")
            log("DETAIL", f"Expected package: {dependency.package}")
            failed = True

    return not failed


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel mandatory dependency manager"
    )
    parser.add_argument(
        "--recover",
        action="store_true",
        help="Automatically install missing mandatory dependencies",
    )
    parser.add_argument(
        "--simulate-missing",
        choices=[dependency.name for dependency in DEPENDENCIES],
        help="TEST ONLY: simulate one mandatory dependency as missing",
    )
    args = parser.parse_args()

    if not validate_host():
        return 1

    if args.simulate_missing:
        log(
            "TEST",
            "Dependency simulation enabled: "
            f"{args.simulate_missing} will be reported as missing.",
        )

    missing = missing_dependencies(args.simulate_missing)

    if not missing:
        log("PASS", "All mandatory Sentinel dependencies are available.")
        return 0

    if not args.recover:
        log("FAIL", "Mandatory Sentinel dependencies are missing.")
        log("SUGGESTION", "Run again with --recover as root.")
        return 1

    if not install_packages(missing):
        return 1

    if not verify_recovery(missing):
        return 1

    log("PASS", "All mandatory Sentinel dependencies are available.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
