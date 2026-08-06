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

- Network scanning
- Device identification
- Service detection
- Inventory updates
- Automatic classification

---

## Inventory

Stores information about every discovered device.

Example:

- IP
- MAC
- Vendor
- Hostname
- Device type
- Services
- Operating system
- Monitoring status

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
