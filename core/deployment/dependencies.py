#!/usr/bin/env python3

import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


def error(message, detail=None, suggestion=None):
    print(f"[ERROR] {message}")
    if detail:
        print(f"[DETAIL] {detail}")
    if suggestion:
        print(f"[SUGGESTION] {suggestion}")


def active_network_interface():
    root = Path("/sys/class/net")
    if not root.is_dir():
        return None

    for interface in root.iterdir():
        if interface.name == "lo":
            continue

        try:
            state = (interface / "operstate").read_text().strip()
        except OSError:
            state = "unknown"

        if state in {"up", "unknown"}:
            return interface.name

    return None


def install_prefix():
    if os.geteuid() == 0:
        return []

    sudo = shutil.which("sudo")
    if not sudo:
        return None

    result = subprocess.run(
        [sudo, "-n", "true"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode == 0:
        return [sudo, "-n"]

    return None


def load_dependencies(metadata_file):
    with metadata_file.open("r", encoding="utf-8") as file:
        metadata = yaml.safe_load(file) or {}

    dependencies = metadata.get("dependencies", [])

    if isinstance(dependencies, list):
        return dependencies, []

    if not isinstance(dependencies, dict):
        raise ValueError("dependencies must be a list or mapping")

    platform = dependencies.get("platform", [])
    host = dependencies.get("host", [])

    if not isinstance(platform, list):
        raise ValueError("dependencies.platform must be a list")

    if not isinstance(host, list):
        raise ValueError("dependencies.host must be a list")

    return platform, host


def check_platform_dependencies(dependencies):
    failed = False

    for dependency in dependencies:
        if dependency == "docker":
            if shutil.which("docker"):
                print("[INFO] Dependency available: docker")
            else:
                error(
                    "Dependency missing: docker",
                    suggestion="Install or enable Docker before continuing.",
                )
                failed = True

        elif dependency == "network":
            interface = active_network_interface()
            if interface:
                print(
                    f"[INFO] Dependency available: network "
                    f"(interface: {interface})"
                )
            else:
                error(
                    "Dependency unavailable: network",
                    suggestion=(
                        "Ensure a non-loopback network interface is up "
                        "before continuing."
                    ),
                )
                failed = True

        else:
            error(
                f"Unsupported platform dependency: {dependency}",
                suggestion=(
                    "Add platform dependency support before deploying "
                    "this module."
                ),
            )
            failed = True

    return not failed


def prepare_host_dependencies(dependencies):
    missing = []
    failed = False

    for index, dependency in enumerate(dependencies, start=1):
        if not isinstance(dependency, dict):
            error(
                f"Invalid host dependency #{index}",
                detail="Expected a mapping.",
            )
            failed = True
            continue

        command = dependency.get("command")
        packages = dependency.get("packages", {})
        required = dependency.get("required", True)

        if not isinstance(command, str) or not command:
            error(
                f"Invalid host dependency #{index}",
                detail="A non-empty command is required.",
            )
            failed = True
            continue

        if shutil.which(command):
            print(f"[INFO] Dependency available: {command}")
            continue

        if not required:
            print(f"[WARN] Optional dependency missing: {command}")
            continue

        if not isinstance(packages, dict):
            error(
                f"Cannot acquire dependency: {command}",
                detail="packages must be a mapping.",
            )
            failed = True
            continue

        package = packages.get("apt")
        if not isinstance(package, str) or not package:
            error(
                f"Cannot acquire dependency automatically: {command}",
                detail="No APT package mapping is declared.",
                suggestion=(
                    "Declare packages.apt or add support for another "
                    "package manager."
                ),
            )
            failed = True
            continue

        print(f"[WARN] Required dependency missing: {command}")
        missing.append((command, package))

    return missing, not failed


def acquire_host_dependencies(missing):
    if not missing:
        return True

    apt_get = shutil.which("apt-get")
    if not apt_get:
        error(
            "Automatic dependency acquisition is unavailable.",
            detail="apt-get was not found.",
            suggestion="Use a supported package manager or install dependencies.",
        )
        return False

    prefix = install_prefix()
    if prefix is None:
        error(
            "Automatic dependency acquisition requires elevated privileges.",
            suggestion=(
                "Run deployment as root or configure passwordless sudo "
                "for package installation."
            ),
        )
        return False

    packages = list(dict.fromkeys(package for _, package in missing))

    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["APT_LISTCHANGES_FRONTEND"] = "none"

    print("[INFO] Updating package metadata...")

    result = subprocess.run(prefix + [apt_get, "update"], env=env)
    if result.returncode != 0:
        error(
            "Dependency acquisition failed.",
            detail="apt-get update failed.",
            suggestion="Verify repository and network connectivity.",
        )
        return False

    print(
        "[INFO] Installing required host package(s): "
        + ", ".join(packages)
    )

    result = subprocess.run(
        prefix + [apt_get, "install", "-y", *packages],
        env=env,
    )
    if result.returncode != 0:
        error(
            "Dependency acquisition failed.",
            detail="One or more required packages could not be installed.",
            suggestion="Verify package repositories and package availability.",
        )
        return False

    failed = False

    for command, package in missing:
        if shutil.which(command):
            print(f"[INFO] Dependency acquired and verified: {command}")
        else:
            error(
                f"Dependency verification failed: {command}",
                detail=(
                    f"Package {package} was installed, but command "
                    f"{command} is still unavailable."
                ),
            )
            failed = True

    return not failed


def main():
    if len(sys.argv) != 2:
        error("Usage: dependencies.py <metadata.yml>")
        return 1

    metadata_file = Path(sys.argv[1])

    if not metadata_file.is_file():
        error(f"Metadata file not found: {metadata_file}")
        return 1

    try:
        platform, host = load_dependencies(metadata_file)
    except (OSError, yaml.YAMLError, ValueError) as exc:
        error("Unable to read dependencies.", detail=str(exc))
        return 1

    if not platform and not host:
        print("[INFO] No dependencies declared.")
        return 0

    platform_ok = check_platform_dependencies(platform)
    missing, host_ok = prepare_host_dependencies(host)

    if not platform_ok or not host_ok:
        return 1

    if not acquire_host_dependencies(missing):
        return 1

    print("[INFO] Dependency validation successful.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
