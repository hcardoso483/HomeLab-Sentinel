#!/usr/bin/env python3


def _row(label, value):
    return f"  {label:<20} {value}"


def _display(value, unavailable="UNKNOWN"):
    if value is None:
        return unavailable
    return str(value)


def render_status(payload):
    lines = []

    overall = payload["overall"]
    not_installed = overall == "NOT INSTALLED"

    lines.append("HomeLab Sentinel Status")
    lines.append("")

    lines.append("Platform")
    lines.append(
        _row(
            "Installation",
            payload["platform"]["installation"],
        )
    )
    lines.append(
        _row(
            "Service identity",
            payload["platform"]["service_identity"],
        )
    )
    lines.append("")

    lines.append("Core API")
    lines.append(
        _row(
            "Service",
            payload["core_api"]["service"],
        )
    )
    lines.append(
        _row(
            "Runtime identity",
            payload["core_api"]["runtime_identity"],
        )
    )
    lines.append(
        _row(
            "Health",
            payload["core_api"]["health"],
        )
    )
    lines.append(
        _row(
            "Endpoint",
            payload["core_api"]["endpoint"],
        )
    )
    lines.append("")

    lines.append("Discovery")
    lines.append(
        _row(
            "Scheduler",
            payload["discovery"]["scheduler"],
        )
    )
    lines.append(
        _row(
            "Schedule",
            payload["discovery"]["schedule"],
        )
    )
    lines.append(
        _row(
            "Schedule policy",
            payload["discovery"]["schedule_policy"],
        )
    )
    lines.append(
        _row(
            "Runtime",
            payload["discovery"]["runtime"],
        )
    )
    lines.append(
        _row(
            "Provider",
            payload["discovery"]["provider"],
        )
    )
    lines.append(
        _row(
            "Last run",
            payload["discovery"]["last_run"],
        )
    )
    lines.append(
        _row(
            "Last success",
            payload["discovery"]["last_success"],
        )
    )
    lines.append(
        _row(
            "Freshness",
            payload["discovery"]["freshness"],
        )
    )
    lines.append(
        _row(
            "Attempt",
            payload["discovery"]["attempt"],
        )
    )
    lines.append(
        _row(
            "Recovery",
            payload["discovery"]["recovery"],
        )
    )
    lines.append("")

    lines.append("Inventory")
    lines.append(
        _row(
            "Database",
            payload["inventory"]["database"],
        )
    )
    lines.append(
        _row(
            "Schema",
            payload["inventory"]["schema"],
        )
    )
    lines.append(
        _row(
            "Integrity",
            payload["inventory"]["integrity"],
        )
    )
    lines.append("")

    lines.append("Monitoring")

    monitoring = payload["monitoring"]
    entities = monitoring["entities"]

    lines.append(
        _row(
            "Scheduler",
            monitoring["scheduler"],
        )
    )
    lines.append(
        _row(
            "Schedule",
            monitoring["schedule"],
        )
    )
    lines.append(
        _row(
            "Reconciliation",
            monitoring["reconciliation"],
        )
    )
    lines.append(
        _row(
            "Provider",
            monitoring["provider"],
        )
    )
    lines.append(
        _row(
            "Collection",
            monitoring["collection"],
        )
    )
    lines.append(
        _row(
            "Evidence",
            monitoring["evidence"],
        )
    )

    unavailable = "N/A" if not_installed else "UNKNOWN"

    lines.append(
        _row(
            "Targets",
            _display(
                monitoring["targets"],
                unavailable,
            ),
        )
    )
    lines.append(
        _row(
            "Healthy",
            _display(
                entities["healthy"],
                unavailable,
            ),
        )
    )
    lines.append(
        _row(
            "Degraded",
            _display(
                entities["degraded"],
                unavailable,
            ),
        )
    )
    lines.append(
        _row(
            "Down",
            _display(
                entities["down"],
                unavailable,
            ),
        )
    )
    lines.append(
        _row(
            "Unknown",
            _display(
                entities["unknown"],
                unavailable,
            ),
        )
    )
    lines.append("")

    lines.append("Verification")

    verification = payload["verification"]

    if not_installed:
        lines.append(
            _row(
                "Post-boot unit",
                verification["post_boot_schedule"],
            )
        )
    else:
        lines.append(
            _row(
                "Post-boot schedule",
                verification["post_boot_schedule"],
            )
        )

        if verification["last_result"] == "IN PROGRESS":
            lines.append(
                _row(
                    "Current verification",
                    "IN PROGRESS",
                )
            )
        else:
            lines.append(
                _row(
                    "Last result",
                    verification["last_result"],
                )
            )

    lines.append("")

    lines.append("Overall")
    lines.append(f"  {overall}")

    text = "\n".join(lines) + "\n"

    if overall == "NOT INSTALLED":
        exit_code = 2
    elif overall == "DEGRADED":
        exit_code = 1
    else:
        exit_code = 0

    return text, exit_code
