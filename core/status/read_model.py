#!/usr/bin/env python3

import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent.parent

if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from core.status import status as legacy
from core.service_discovery import service_discovery as service_discovery_core

STATUS_SCHEMA_VERSION = 1


def _service_active(unit):
    result = legacy.run_command(
        "systemctl",
        "is-active",
        unit,
    )
    return (
        result.returncode == 0
        and result.stdout.strip() == "active"
    )


def _service_enabled(unit):
    result = legacy.run_command(
        "systemctl",
        "is-enabled",
        unit,
    )
    return (
        result.returncode == 0
        and result.stdout.strip() == "enabled"
    )



def _timer_policy(unit):
    value = legacy.service_property(
        unit,
        "TimersMonotonic",
    )

    if not value:
        return None

    marker = "OnUnitInactiveUSec="

    for line in value.splitlines():
        if marker not in line:
            continue

        policy = line.split(marker, 1)[1]
        policy = policy.split(";", 1)[0].strip()

        if policy:
            return policy

    return None


def _timer_status(unit):
    active_state = legacy.service_property(
        unit,
        "ActiveState",
    )
    sub_state = legacy.service_property(
        unit,
        "SubState",
    )
    unit_file_state = legacy.service_property(
        unit,
        "UnitFileState",
    )

    if active_state == "active" and sub_state == "running":
        runtime = "RUNNING"
    elif active_state == "active" and sub_state == "waiting":
        runtime = "WAITING"
    elif active_state == "inactive":
        runtime = "INACTIVE"
    else:
        runtime = "UNKNOWN"

    last_trigger = legacy.service_property(
        unit,
        "LastTriggerUSec",
    )
    next_elapse_monotonic = legacy.service_property(
        unit,
        "NextElapseUSecMonotonic",
    )

    return {
        "state": (
            active_state.upper()
            if active_state
            else "UNKNOWN"
        ),
        "runtime": runtime,
        "enabled": unit_file_state == "enabled",
        "schedule": _timer_policy(unit),
        "last_trigger": last_trigger or None,
        "next_elapse_monotonic": (
            None
            if not next_elapse_monotonic
            or next_elapse_monotonic == "infinity"
            else next_elapse_monotonic
        ),
    }


def build_status(
    *,
    simulation=None,
    ignore_verification_result=False,
    api_health_probe=None,
):
    """
    Build the canonical structured HomeLab Sentinel platform status.

    This function evaluates platform state but performs no presentation.
    Callers decide how the returned model is rendered or transported.

    api_health_probe is injectable so API consumers do not need to make
    a recursive HTTP request back into the Core API.
    """

    degraded = False
    not_installed = False

    def fail():
        nonlocal degraded
        degraded = True

    def missing():
        nonlocal not_installed
        not_installed = True

    payload = {
        "schema_version": STATUS_SCHEMA_VERSION,
        "platform": {},
        "core_api": {},
        "discovery": {},
        "inventory": {},
        "service_discovery": {},
        "monitoring": {},
        "verification": {},
        "overall": "READY",
    }

    # ------------------------------------------------------------
    # Platform
    # ------------------------------------------------------------

    installation_present = legacy.APP_ROOT.is_dir()

    if simulation == "not-installed":
        installation_present = False

    if installation_present:
        payload["platform"]["installation"] = "READY"
    else:
        payload["platform"]["installation"] = "NOT INSTALLED"
        missing()

    if not installation_present:
        payload["platform"]["service_identity"] = "N/A"

        payload["core_api"] = {
            "service": "N/A",
            "runtime_identity": "N/A",
            "health": "N/A",
            "endpoint": "127.0.0.1:8000",
        }

        payload["discovery"] = {
            "scheduler": "N/A",
            "schedule": "N/A",
            "schedule_policy": "N/A",
            "runtime": "N/A",
            "provider": "N/A",
            "last_run": "N/A",
            "last_success": "N/A",
            "freshness": "N/A",
            "attempt": "N/A",
            "recovery": "N/A",
        }

        payload["inventory"] = {
            "database": "N/A",
            "schema": "N/A",
            "integrity": "N/A",
        }

        payload["service_discovery"] = {
            "readiness": "N/A",
            "provider": "N/A",
            "targets": None,
            "endpoints": {
                "observed": None,
                "stale": None,
            },
            "last_inspection": None,
            "retry_pool": None,
            "normal_timer": {
                "state": "UNKNOWN",
                "runtime": "UNKNOWN",
                "enabled": None,
                "schedule": None,
                "last_trigger": None,
                "next_elapse_monotonic": None,
            },
            "retry_timer": {
                "state": "UNKNOWN",
                "runtime": "UNKNOWN",
                "enabled": None,
                "schedule": None,
                "last_trigger": None,
                "next_elapse_monotonic": None,
            },
        }
        payload["monitoring"] = {
            "scheduler": "N/A",
            "schedule": "N/A",
            "reconciliation": "N/A",
            "provider": "N/A",
            "collection": "N/A",
            "evidence": "N/A",
            "targets": None,
            "entities": {
                "healthy": None,
                "degraded": None,
                "down": None,
                "unknown": None,
            },
        }

        payload["verification"] = {
            "post_boot_schedule": "N/A",
            "last_result": "N/A",
        }

        payload["overall"] = "NOT INSTALLED"
        return payload

    user = legacy.service_property(
        legacy.API_UNIT,
        "User",
    )
    group = legacy.service_property(
        legacy.API_UNIT,
        "Group",
    )

    if simulation == "wrong-runtime-identity":
        user = "wrong-user"
        group = "wrong-group"

    if (
        user == legacy.EXPECTED_USER
        and group == legacy.EXPECTED_GROUP
    ):
        payload["platform"]["service_identity"] = "READY"
    elif user is None or group is None:
        payload["platform"]["service_identity"] = "UNKNOWN"
        fail()
    else:
        payload["platform"]["service_identity"] = (
            f"INCORRECT ({user or '?'}:{group or '?'})"
        )
        fail()

    # ------------------------------------------------------------
    # Core API
    # ------------------------------------------------------------

    if _service_active(legacy.API_UNIT):
        payload["core_api"]["service"] = "ACTIVE"
    else:
        payload["core_api"]["service"] = "INACTIVE"
        fail()

    runtime_user = legacy.service_property(
        legacy.API_UNIT,
        "User",
    )
    runtime_group = legacy.service_property(
        legacy.API_UNIT,
        "Group",
    )

    if simulation == "wrong-runtime-identity":
        runtime_user = "wrong-user"
        runtime_group = "wrong-group"

    if (
        runtime_user == legacy.EXPECTED_USER
        and runtime_group == legacy.EXPECTED_GROUP
    ):
        payload["core_api"]["runtime_identity"] = "CORRECT"
    else:
        payload["core_api"]["runtime_identity"] = "INCORRECT"
        fail()

    if api_health_probe is None:
        api_health_probe = legacy.api_health

    try:
        api_healthy = bool(api_health_probe())
    except Exception:
        api_healthy = False

    if api_healthy:
        payload["core_api"]["health"] = "HEALTHY"
    else:
        payload["core_api"]["health"] = "UNHEALTHY"
        fail()

    payload["core_api"]["endpoint"] = "127.0.0.1:8000"

    # ------------------------------------------------------------
    # Discovery
    # ------------------------------------------------------------

    reconciliation = legacy.discovery_reconciliation_status()

    if reconciliation is not None:
        reconciliation = dict(reconciliation)

    if simulation == "discovery-scheduler-disabled":
        if reconciliation is None:
            reconciliation = {
                "active": False,
                "enabled": False,
                "compliant": False,
            }
        else:
            reconciliation["active"] = False
            reconciliation["enabled"] = False

    elif simulation == "discovery-schedule-drift":
        if reconciliation is None:
            reconciliation = {
                "active": True,
                "enabled": True,
                "compliant": False,
            }
        else:
            reconciliation["compliant"] = False

    if reconciliation is None:
        payload["discovery"]["scheduler"] = "INACTIVE"
        payload["discovery"]["schedule"] = "DISABLED"
        payload["discovery"]["schedule_policy"] = "UNKNOWN"
        fail()
    else:
        if reconciliation["active"]:
            payload["discovery"]["scheduler"] = "ACTIVE"
        else:
            payload["discovery"]["scheduler"] = "INACTIVE"
            fail()

        if reconciliation["enabled"]:
            payload["discovery"]["schedule"] = "ENABLED"
        else:
            payload["discovery"]["schedule"] = "DISABLED"
            fail()

        if reconciliation["compliant"]:
            payload["discovery"]["schedule_policy"] = "COMPLIANT"
        else:
            payload["discovery"]["schedule_policy"] = "DRIFT"
            fail()

    discovery = legacy.discovery_runtime_status()

    if simulation == "discovery-state-unreadable":
        discovery = {"readable": False}

    elif simulation in {
        "discovery-failed",
        "discovery-recovering",
        "discovery-running",
    }:
        simulated = dict(discovery or {})
        simulated["readable"] = True
        simulated.setdefault("provider", "nmap")
        simulated.setdefault(
            "last_success_at",
            "2026-01-01T00:00:00Z",
        )
        simulated.setdefault("attempt", 1)
        simulated.setdefault("max_attempts", 2)

        if simulation == "discovery-failed":
            simulated["state"] = "FAILED"
            simulated["freshness"] = "STALE"
            simulated["attempt"] = 2
            simulated["recovery_action"] = "retry"
            simulated["recovery_result"] = "failed"

        elif simulation == "discovery-recovering":
            simulated["state"] = "RECOVERING"
            simulated["freshness"] = "STALE"
            simulated["attempt"] = 1
            simulated["recovery_action"] = "retry"
            simulated["recovery_result"] = "in-progress"

        else:
            simulated["state"] = "RUNNING"
            simulated["freshness"] = "UNKNOWN"
            simulated["attempt"] = 1
            simulated["recovery_action"] = "none"
            simulated["recovery_result"] = "not-attempted"

        discovery = simulated

    if discovery is None:
        payload["discovery"].update({
            "runtime": "NEVER RUN",
            "provider": "N/A",
            "last_run": "NEVER RUN",
            "last_success": "N/A",
            "freshness": "UNKNOWN",
            "attempt": "N/A",
            "recovery": "UNKNOWN",
        })
        fail()

    elif not discovery.get("readable"):
        payload["discovery"].update({
            "runtime": "UNKNOWN",
            "provider": "UNKNOWN",
            "last_run": "UNKNOWN",
            "last_success": "UNKNOWN",
            "freshness": "UNKNOWN",
            "attempt": "UNKNOWN",
            "recovery": "UNKNOWN",
        })
        fail()

    else:
        runtime_state = discovery.get("state") or "UNKNOWN"
        freshness = discovery.get("freshness") or "UNKNOWN"

        if runtime_state == "SUCCESS" and freshness == "FRESH":
            runtime = "HEALTHY"
        elif runtime_state == "RUNNING":
            runtime = "RUNNING"
        elif runtime_state == "RECOVERING":
            runtime = "RECOVERING"
            fail()
        elif runtime_state == "FAILED":
            runtime = "DEGRADED"
            fail()
        else:
            runtime = "UNKNOWN"
            fail()

        if runtime_state == "RUNNING":
            freshness_value = "IN PROGRESS"
        elif freshness == "FRESH":
            freshness_value = "FRESH"
        else:
            freshness_value = freshness
            fail()

        attempt = discovery.get("attempt")
        max_attempts = discovery.get("max_attempts")

        if attempt is None or max_attempts is None:
            attempt_value = "UNKNOWN"
        else:
            attempt_value = f"{attempt}/{max_attempts}"

        recovery_result = discovery.get("recovery_result")

        if recovery_result == "not-attempted":
            recovery = "NOT REQUIRED"
        elif recovery_result == "recovered":
            recovery = "RECOVERED"
        elif recovery_result == "in-progress":
            recovery = "IN PROGRESS"
            fail()
        elif recovery_result == "failed":
            recovery = "FAILED"
            fail()
        else:
            recovery = recovery_result or "UNKNOWN"
            fail()

        payload["discovery"].update({
            "runtime": runtime,
            "provider": discovery.get("provider") or "UNKNOWN",
            "last_run": runtime_state,
            "last_success": (
                discovery.get("last_success_at") or "N/A"
            ),
            "freshness": freshness_value,
            "attempt": attempt_value,
            "recovery": recovery,
        })

    # ------------------------------------------------------------
    # Inventory
    # ------------------------------------------------------------

    version, integrity = legacy.inventory_status()

    if simulation == "missing-database":
        version, integrity = None, None

    elif simulation == "unsupported-schema":
        version, integrity = 1, "ok"

    if version is None:
        payload["inventory"] = {
            "database": "MISSING",
            "schema": "UNKNOWN",
            "integrity": "UNKNOWN",
        }
        fail()

    elif version == "error":
        payload["inventory"] = {
            "database": "UNREADABLE",
            "schema": "UNKNOWN",
            "integrity": "UNKNOWN",
        }
        fail()

    else:
        payload["inventory"]["database"] = "READY"

        if version >= 2:
            payload["inventory"]["schema"] = f"v{version}"
        else:
            payload["inventory"]["schema"] = (
                f"UNSUPPORTED v{version}"
            )
            fail()

        if integrity == "ok":
            payload["inventory"]["integrity"] = "OK"
        else:
            payload["inventory"]["integrity"] = str(integrity)
            fail()

    # ------------------------------------------------------------
    # Service Discovery
    # ------------------------------------------------------------

    try:
        service_discovery_status = (
            service_discovery_core.service_discovery_status(
                legacy.DATABASE
            )
        )

        service_discovery_targets = (
            service_discovery_core.service_discovery_targets(
                legacy.DATABASE
            )
        )

        connection = (
            service_discovery_core.connect_read_only(
                legacy.DATABASE
            )
        )

        try:
            retry_pool = (
                service_discovery_core.service_discovery_retry_pool(
                    connection,
                    service_discovery_targets,
                )
            )
        finally:
            connection.close()

        normal_timer = _timer_status(
            legacy.SERVICE_DISCOVERY_TIMER
        )

        retry_timer = _timer_status(
            legacy.SERVICE_DISCOVERY_RETRY_TIMER
        )

    except Exception:
        payload["service_discovery"] = {
            "readiness": "UNAVAILABLE",
            "provider": "UNKNOWN",
            "targets": None,
            "endpoints": {
                "observed": None,
                "stale": None,
            },
            "last_inspection": None,
            "retry_pool": None,
            "normal_timer": {
                "state": "UNKNOWN",
                "runtime": "UNKNOWN",
                "enabled": None,
                "schedule": None,
                "last_trigger": None,
                "next_elapse_monotonic": None,
            },
            "retry_timer": {
                "state": "UNKNOWN",
                "runtime": "UNKNOWN",
                "enabled": None,
                "schedule": None,
                "last_trigger": None,
                "next_elapse_monotonic": None,
            },
        }
        fail()
    else:
        payload["service_discovery"] = {
            "readiness": "READY",
            "provider": service_discovery_status["provider"],
            "targets": service_discovery_status["targets"],
            "endpoints": service_discovery_status["endpoints"],
            "last_inspection": (
                service_discovery_status["last_inspection"]
            ),
            "retry_pool": len(retry_pool),
            "normal_timer": normal_timer,
            "retry_timer": retry_timer,
        }

    # ------------------------------------------------------------
    # Monitoring
    # ------------------------------------------------------------

    if simulation is not None:
        # Simulations must be deterministic.  Unrelated simulated
        # subsystems must not inherit transient live Monitoring state.
        payload["monitoring"]["scheduler"] = "ACTIVE"
        payload["monitoring"]["schedule"] = "ENABLED"
        payload["monitoring"]["reconciliation"] = "HEALTHY"
        payload["monitoring"]["provider"] = "prometheus"

        collection = "HEALTHY"
        if simulation == "monitoring-collection-failed":
            collection = "FAILED"

        payload["monitoring"]["collection"] = collection

        if collection not in {
            "HEALTHY",
            "IN PROGRESS",
        }:
            fail()

        monitoring_health = {
            "counts": {
                "HEALTHY": 3,
                "DEGRADED": 0,
                "DOWN": 0,
                "UNKNOWN": 0,
            },
            "targets": 3,
            "freshness": "FRESH",
        }

        if simulation == "monitoring-entities-down":
            monitoring_health = {
                "counts": {
                    "HEALTHY": 1,
                    "DEGRADED": 0,
                    "DOWN": 2,
                    "UNKNOWN": 0,
                },
                "targets": 3,
                "freshness": "FRESH",
            }

        evidence = monitoring_health["freshness"]

        if simulation == "monitoring-evidence-stale":
            evidence = "STALE"

        payload["monitoring"]["evidence"] = evidence

        if evidence != "FRESH":
            fail()

        counts = monitoring_health["counts"]

        payload["monitoring"]["targets"] = (
            monitoring_health["targets"]
        )

        payload["monitoring"]["entities"] = {
            "healthy": counts["HEALTHY"],
            "degraded": counts["DEGRADED"],
            "down": counts["DOWN"],
            "unknown": counts["UNKNOWN"],
        }

    else:
        monitoring_timer_active = (
            legacy.service_property(
                legacy.MONITORING_TIMER,
                "ActiveState",
            ) == "active"
        )

        monitoring_timer_enabled = (
            legacy.service_property(
                legacy.MONITORING_TIMER,
                "UnitFileState",
            ) == "enabled"
        )

        if monitoring_timer_active:
            payload["monitoring"]["scheduler"] = "ACTIVE"
        else:
            payload["monitoring"]["scheduler"] = "INACTIVE"
            fail()

        if monitoring_timer_enabled:
            payload["monitoring"]["schedule"] = "ENABLED"
        else:
            payload["monitoring"]["schedule"] = "DISABLED"
            fail()

        reconciliation_timer_active = (
            legacy.service_property(
                legacy.MONITORING_RECONCILE_TIMER,
                "ActiveState",
            ) == "active"
        )

        reconciliation_timer_enabled = (
            legacy.service_property(
                legacy.MONITORING_RECONCILE_TIMER,
                "UnitFileState",
            ) == "enabled"
        )

        reconciliation_health = legacy.oneshot_health(
            legacy.MONITORING_RECONCILE_UNIT
        )

        if not (
            reconciliation_timer_active
            and reconciliation_timer_enabled
        ):
            reconciliation_health = "FAILED"

        payload["monitoring"]["reconciliation"] = (
            reconciliation_health
        )

        if reconciliation_health not in {
            "HEALTHY",
            "IN PROGRESS",
        }:
            fail()

        provider = legacy.monitoring_provider_status()

        if provider is None:
            payload["monitoring"]["provider"] = "UNKNOWN"
            fail()
        else:
            payload["monitoring"]["provider"] = provider

        collection = legacy.oneshot_health(
            legacy.MONITORING_UNIT
        )

        payload["monitoring"]["collection"] = collection

        if collection not in {
            "HEALTHY",
            "IN PROGRESS",
        }:
            fail()

        monitoring_health = legacy.monitoring_health_status()

        if monitoring_health is None:
            payload["monitoring"].update({
                "evidence": "UNKNOWN",
                "targets": None,
                "entities": {
                    "healthy": None,
                    "degraded": None,
                    "down": None,
                    "unknown": None,
                },
            })
            fail()

        else:
            evidence = monitoring_health["freshness"]

            payload["monitoring"]["evidence"] = evidence

            if evidence != "FRESH":
                fail()

            counts = monitoring_health["counts"]

            payload["monitoring"]["targets"] = (
                monitoring_health["targets"]
            )

            payload["monitoring"]["entities"] = {
                "healthy": counts["HEALTHY"],
                "degraded": counts["DEGRADED"],
                "down": counts["DOWN"],
                "unknown": counts["UNKNOWN"],
            }

    # ------------------------------------------------------------
    # Verification
    # ------------------------------------------------------------

    if _service_enabled(legacy.VERIFY_TIMER):
        payload["verification"][
            "post_boot_schedule"
        ] = "ENABLED"
    else:
        payload["verification"][
            "post_boot_schedule"
        ] = "DISABLED"
        fail()

    verify_active = legacy.service_property(
        legacy.VERIFY_UNIT,
        "ActiveState",
    )
    verify_result = legacy.service_property(
        legacy.VERIFY_UNIT,
        "Result",
    )
    verify_exit = legacy.service_property(
        legacy.VERIFY_UNIT,
        "ExecMainStatus",
    )

    if simulation == "failed-verification":
        verify_active = "failed"
        verify_result = "exit-code"
        verify_exit = "1"

    elif simulation == "verification-running":
        verify_active = "activating"
        verify_result = "exit-code"
        verify_exit = "1"

    if ignore_verification_result:
        payload["verification"]["last_result"] = (
            "IGNORED (verification context)"
        )

    elif verify_active in ("activating", "active"):
        payload["verification"]["last_result"] = "IN PROGRESS"

    elif verify_result == "success" and verify_exit == "0":
        payload["verification"]["last_result"] = "SUCCESS"

    elif verify_result is None or verify_exit is None:
        payload["verification"]["last_result"] = "UNKNOWN"
        fail()

    else:
        payload["verification"]["last_result"] = (
            f"FAILED ({verify_result or 'unknown'}, "
            f"exit {verify_exit or '?'})"
        )
        fail()

    # ------------------------------------------------------------
    # Overall
    # ------------------------------------------------------------

    if not_installed:
        payload["overall"] = "NOT INSTALLED"
    elif degraded:
        payload["overall"] = "DEGRADED"
    else:
        payload["overall"] = "READY"

    return payload
