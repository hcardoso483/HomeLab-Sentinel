# HomeLab Sentinel

> **One dashboard. Complete visibility.**

HomeLab Sentinel is an open-source, self-hosted monitoring platform designed for homelab enthusiasts, makers, and small infrastructures. Its goal is to provide a single, unified interface for discovering, monitoring, and managing an entire homelab without requiring users to manually piece together multiple tools.

## Vision

Modern homelabs often rely on several excellent tools for monitoring, logging, discovery, dashboards, and alerting. While each tool is powerful, deploying and integrating them into a cohesive solution can be challenging, especially for newcomers.

HomeLab Sentinel aims to solve that problem.

Rather than replacing existing open-source projects, HomeLab Sentinel brings them together into a single, intelligent platform that is easy to deploy, easy to maintain, and easy to understand.

Our long-term goal is simple:

* Automatically discover devices on the network.
* Build and maintain a living inventory of the homelab.
* Detect running services and open ports.
* Monitor CPU, memory, storage, containers, virtual machines, and applications.
* Collect historical metrics.
* Generate meaningful alerts.
* Present everything through a single, unified dashboard.

The platform should require as little manual configuration as possible.

## Core Principles

* **Automatic Discovery** – If HomeLab Sentinel can detect it automatically, the user should not have to configure it manually.
* **Single Dashboard** – One place to view the entire infrastructure.
* **Modular Architecture** – Components can be enabled, disabled, or replaced without redesigning the platform.
* **Open Source** – Built openly and improved with community feedback.
* **Beginner Friendly** – Powerful enough for experienced users while remaining approachable for newcomers.
* **Production Mindset** – Reliable, reproducible deployments with clear documentation and sensible defaults.

## Planned Features

### Network Discovery

* Automatic IP discovery
* Device identification
* Hostname resolution
* MAC vendor detection
* Operating system detection (best effort)

### Service Discovery

* Open port detection
* Service identification
* Docker host detection
* Proxmox detection
* NAS detection
* Home Assistant detection
* Web application discovery

### Monitoring

* CPU
* Memory
* Storage
* SMART disks
* Docker containers
* Virtual machines
* Services
* Network performance
* Historical metrics

### Alerts

* Email
* Discord
* Telegram
* Webhooks
* Intelligent health notifications

### Dashboard

A single interface providing:

* Device inventory
* Service inventory
* Container status
* Resource utilization
* Alerts
* Historical trends
* Recent infrastructure changes

## Project Philosophy

HomeLab Sentinel is not intended to reinvent the excellent monitoring software that already exists.

Instead, it provides an intelligent layer that discovers infrastructure, integrates proven open-source technologies, automates their deployment and configuration, and presents the results through a consistent experience.

The objective is to reduce complexity while preserving flexibility.

## Project Origins

HomeLab Sentinel began as an idea during a series of design sessions between the project creator and ChatGPT.

The project creator defined the vision, goals, priorities, and user experience, with a strong emphasis on automatic discovery, simplicity, and creating a platform that anyone with a homelab could deploy and use.

The technical architecture, implementation guidance, deployment strategy, Linux layout, Docker design, and documentation were developed collaboratively during those sessions with assistance from ChatGPT.

This repository documents that collaborative process as the project evolves in public.

## Current Status

**Version:** 0.1.0-alpha

The project is currently in the foundation phase.

Current work includes:

* Establishing the project architecture
* Creating the installer framework
* Building the modular Docker stack
* Designing the discovery engine
* Preparing the monitoring platform

## Contributing

Contributions, suggestions, bug reports, and feature requests are welcome.

If you have ideas that improve usability, discovery, monitoring, or documentation, please open an issue or submit a pull request.

## License

This project is released under the MIT License.

## Acknowledgements

HomeLab Sentinel is the result of a collaborative design process.

The project vision, direction, testing, and long-term goals are driven by the repository owner.

The technical architecture, implementation guidance, software design, deployment strategy, and much of the documentation have been developed collaboratively with assistance from OpenAI's ChatGPT.

The intention is to be transparent about how the project is being created while welcoming future contributions from the open-source community.

