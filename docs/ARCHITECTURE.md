# HomeLab Sentinel Architecture

## Overview

HomeLab Sentinel is designed as a modular platform that automatically discovers, monitors, and manages homelab infrastructure.

Rather than replacing existing open-source software, HomeLab Sentinel integrates proven technologies into a single cohesive platform.

The goal is to provide a unified experience with minimal manual configuration.

---

# Design Principles

1. Automatic discovery first
2. One dashboard
3. Modular architecture
4. Easy installation
5. Intelligent defaults
6. Open-source and community driven

---

# High Level Architecture

                    HomeLab Sentinel

                             │
                             │
        ┌────────────────────┴────────────────────┐
        │                                         │
 Discovery Engine                          Configuration Manager
        │                                         │
        └────────────────────┬────────────────────┘
                             │
                      Inventory Database
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
 Monitoring Engine      Alert Manager       Dashboard
        │                    │                    │
        └────────────────────┴────────────────────┘

---

# Core Components

## Discovery Engine

Responsible for:

- Discovery scope orchestration
- Discovery provider execution
- Network and host observation collection
- Discovery record validation
- Forwarding validated observations to the Sentinel Core

The Discovery Engine produces observations. It does not assign permanent device identities or write provider-specific results directly into inventory.

---

## Inventory

The Inventory is the Sentinel Core representation of discovered infrastructure.

Responsibilities include:

- Correlating validated observations
- Maintaining permanent device identities
- Tracking current device state
- Preserving historical observations
- Associating IP addresses, MAC addresses, hostnames, services, and other discovered attributes
- Supporting device classification and monitoring state

Discovery observations do not become permanent devices until they have been processed by the Core inventory and correlation layers.

---

## Monitoring

Collects:

- CPU
- RAM
- Disk
- Docker
- Virtual Machines
- Network
- Historical metrics

---

## Alerts

Provides notifications through:

- Email
- Discord
- Telegram
- Webhooks

---

## Dashboard

Displays:

- Devices
- Containers
- Alerts
- Historical graphs
- Service status

---

# Project Philosophy

If HomeLab Sentinel can detect something automatically,
the user should never have to configure it manually.

Automatic discovery is the foundation of the platform.

Everything else builds upon the discovered inventory.

No component shall rely on hard-coded filesystem paths to locate modules. Module discovery must occur through the Registry.

| Module                      | Technology    |    Status   |
| --------------------------- | ------------- | :---------: |
| Dashboard Module            | Homepage      | ✅ Complete |
| Metrics Module              | Prometheus    |  ⏳ Planned |
| Host Monitoring Module      | Node Exporter |  ⏳ Planned |
| Container Monitoring Module | cAdvisor      |  ⏳ Planned |
| Visualization Module        | Grafana       |  ⏳ Planned |
| Discovery Module            | Custom        |  ⏳ Planned |
| Sentinel Engine             | Custom        |  ⏳ Planned |
