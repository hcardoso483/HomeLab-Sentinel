# Prometheus Module

**Category:** Monitoring

**Module ID:** prometheus

**Status:** Enabled

---

# Overview

The Prometheus module provides time-series metrics collection for HomeLab Sentinel.

It is responsible for collecting, storing, and exposing performance metrics from monitored systems and services. These metrics form the foundation for dashboards, alerting, and historical analysis throughout the platform.

This module serves as the primary metrics provider for HomeLab Sentinel.

---

# Purpose

The purpose of this module is to:

* Collect system metrics
* Store historical performance data
* Provide a central metrics database
* Supply data to visualization modules such as Grafana
* Supply data to future alerting and analytics modules

---

# Services

| Service    | Description                                        |
| ---------- | -------------------------------------------------- |
| Prometheus | Time-series metrics database and collection engine |

---

# Default Port

| Port | Protocol | Purpose                          |
| ---- | -------- | -------------------------------- |
| 9090 | TCP      | Prometheus Web Interface and API |

---

# Storage

The module stores its time-series database in a persistent Docker volume.

Persistent storage ensures that historical metrics survive container restarts and software updates.

---

# Configuration

Main configuration file:

```text
config/prometheus.yml
```

This file defines:

* Scrape intervals
* Targets
* Collection rules

Additional targets will be added automatically by future HomeLab Sentinel modules.

---

# Dependencies

Required:

* Docker Engine
* Docker Compose

Optional:

* Node Exporter
* cAdvisor
* Grafana

---

# Health Checks

The module verifies:

* Container status
* Prometheus service availability
* HTTP health endpoint
* Configuration validity

Health information is reported to the Sentinel Core.

---

# Troubleshooting

If Prometheus is unavailable:

1. Verify the container is running.
2. Check the container logs.
3. Confirm that port **9090** is available.
4. Validate the configuration file.
5. Verify Docker networking.

---

# Future Enhancements

Planned improvements include:

* Automatic target discovery
* Dynamic configuration generation
* Alert rule integration
* High availability support
* Long-term storage integration
* Automatic service registration

---

# Related Modules

This module is designed to integrate with:

* Node Exporter
* cAdvisor
* Grafana
* Alert Manager
* Discovery Engine
* Sentinel Core

---

# Maintainers

HomeLab Sentinel Project

---

# License

This module is distributed as part of the HomeLab Sentinel project.
