---
id: scripts
summary: Complete reference for all shell scripts — installation, sync, update, maintenance, security, and utilities
tags: [scripts, automation, installation, maintenance, deployment]
related_files: [*.sh, scripts/**]
date: 2026-02-15
status: published
---

# Scripts Documentation

Complete reference for all shell scripts in this repository.

## Sub-documents

| Doc | Description |
|-----|-------------|
| [installation.md](installation.md) | install.sh, deploy.sh, set_environment.sh, stop_external_drives.sh, startup_services.sh, flatpak-reconcile.sh |
| [sync-update.md](sync-update.md) | sync.sh, sync-system.sh, sync-user.sh, sync-posthook.sh, update.sh, upgrade.sh, pull.sh |
| [maintenance.md](maintenance.md) | maintenance.sh, autoSystemUpdate.sh, autoUserUpdate.sh |
| [security.md](security.md) | harden.sh, soften.sh, cleanIPTABLESrules.sh |
| [utility.md](utility.md) | fix-terminals, generate_docs_index.py, handle_docker.sh, background-test.sh, helper scripts |

## Overview

Scripts are located in the repository root and can be run directly or via the `aku` wrapper command.

### Script Categories

- **Installation**: Initial setup and installation
- **Synchronization**: Applying configuration changes
- **Update**: Updating flake inputs and system
- **Maintenance**: System cleanup and optimization
- **Security**: File permissions and hardening
- **Utility**: Helper scripts for specific tasks

### Quick Reference

| Script | Purpose | Usage | Requires Sudo |
|--------|---------|-------|---------------|
| `install.sh` | Main installation | `./install.sh <path> <profile> [-s]` | Yes |
| `sync.sh` | Sync system + user | `./sync.sh` or `aku sync` | Yes (system) |
| `sync-system.sh` | Sync system only | `./sync-system.sh` or `aku sync system` | Yes |
| `sync-user.sh` | Sync user only | `./sync-user.sh` or `aku sync user` | No |
| `update.sh` | Update flake.lock | `./update.sh` or `aku update` | Yes |
| `upgrade.sh` | Update + sync | `./upgrade.sh [path] [profile] [-s]` or `aku upgrade` | Yes |
| `pull.sh` | Pull from git | `./pull.sh` or `aku pull` | Yes (temporarily) |
| `maintenance.sh` | System cleanup | `./maintenance.sh [-s]` | Yes (some tasks) |
| `harden.sh` | Secure files | `sudo ./harden.sh [path]` or `aku harden` | Yes |
| `soften.sh` | Relax permissions | `sudo ./soften.sh [path]` or `aku soften` | Yes |

### Script Dependencies Graph

```
install.sh
├── set_environment.sh
├── handle_docker.sh
├── stop_external_drives.sh
├── update.sh
├── harden.sh
├── soften.sh
├── sync-system.sh
├── sync-user.sh
│   └── sync-posthook.sh
├── maintenance.sh
└── startup_services.sh

upgrade.sh
├── handle_docker.sh
├── update.sh
└── sync.sh
    ├── sync-system.sh
    └── sync-user.sh
        └── sync-posthook.sh
```
