# Infra Alerts — Telegram alerting, deploy announcements and the ops bot (AINF-368)

Group **Infra Alerts** (forum supergroup, bot `@infra_alerts_aku_bot`). Topics:
`General` = bot commands · `🚀 Deploys` · `🚨 Alerts` · `📋 Weekly`.

## Pieces

| Piece | Module | Runs on | Flag |
|---|---|---|---|
| Alertmanager (delivery of every Prometheus rule) | `system/app/alertmanager.nix` | VPS | `grafanaEnable` |
| Host-health textfile (docker daemons, failed units) | `system/app/prometheus-host-health.nix` | VPS, NAS | `prometheusHostHealthEnable` |
| Deploy announcements + post-deploy check | `system/app/infra-notify.nix` (called by `install.sh`, `autoSystemUpdate.sh`) | every node | `infraNotifyEnable`, `infraNodeName`, `infraBotUrl` |
| Bot: relay + commands + Sunday digest | `system/app/infra-bot.nix` + `infra-bot.py` | VPS | `infraBotEnable` |
| `/restart` target + sudoers | `system/app/infra-restart.nix` | VPS, NAS | `infraRestartEnable` |
| Dead-man's switch ping | `system/app/healthchecks-ping.nix` + pfSense cron | VPS, pfSense | `healthchecksPingUrl` |

## Alert routing
- `critical` → 🚨 Alerts **once** per problem (`repeat_interval 168h`, AM retention 240h) + 🟢 resolved; also email.
- `warning` → 🚨 Alerts too (🟡, once + resolved), no email; the bot posts the Sunday 10:00 digest to 📋 Weekly.
- `node="nas"` muted 23:00–16:05 Europe/Warsaw (NAS sleep timer). `HostDown` inhibits the node's other alerts.
- Every scrape job carries `node` + `role`: `always_on` (VPS, NAS, pfSense) gets `HostDown`; `roaming` (DESK, X13, LAPTOP_A, DESK_A) only disk / RAM / failed units / stale update while up. Set `role` in `prometheusRemoteTargets`.
- Message format: `🔴 CRITICAL · <node> · <AlertName>` + summary + description; `🟢 RESOLVED · …`.

## Deploys
`install.sh` / `autoSystemUpdate.sh` call `infra-notify deploy` at every outcome (ok / warn / failed / rollback / boot mode).
The message: status, profile, host, generations, commit, duration, who/via, then a post-deploy check
(docker daemons, containers not running, failed system+user units, disk, the node's active alerts).
- Nodes holding the token (VPS, NAS, DESK, X13) post to Telegram directly — the profile must map
  `grafanaTelegramBotToken/ChatId` + `infraTelegramDeploysThreadId` from secrets.
- Secrets-free nodes (LAPTOP_A, DESK_A, user `aga`) POST to the bot relay `http://100.64.0.6:8765/deploy`
  over Tailscale; identity = source Tailscale IP. No token on those machines.
- `infra-notify check` prints the health block by hand.

## Bot commands
`/status` · `/status <node> [full]` · `/alerts` · `/deploys` · `/help` — read-only, answered in the topic used.
`/restart <vps|nas> <docker-rootless|docker-rootful>` — admins (`infraTelegramAdminUserIds`) only; runs
`infra-restart --check` first, asks with ✅/❌ (2 min), then `sudo -n infra-restart` locally or over BatchMode
ssh (`infraRestartSshTargets`). Result is edited into the confirmation message.
`infra-bot --selftest` renders every handler without Telegram.

## Dead-man's switch
healthchecks.io checks `vps-alive` (VPS timer, 5 min) and `pfsense-alive` (pfSense cron job created via the
REST API `services/cron/job`, `/usr/bin/fetch` every 5 min). Ping URLs in `secrets/domains.nix`.

## Testing
- Synthetic critical: write a textfile with the SAME `# HELP`/`# TYPE` lines as `host_health.prom` and
  `host_docker_daemon_up{mode="test"} 0` into `/var/lib/prometheus-node-exporter/textfile/` on the VPS →
  `DockerDaemonDown` fires after 3 min; delete the file → 🟢 resolved at the next 5-min group tick.
  Do not restart Alertmanager in between (a restart loses a pending resolve).
- Restart path without a restart: `sudo -n infra-restart docker-rootless --check` (VPS) and
  `env -u SSH_AUTH_SOCK ssh -o BatchMode=yes akunito@100.64.0.1 sudo -n infra-restart docker-rootful --check`.

## Gotchas
See memory `reference_infra_alerts_telegram_stack` and the module headers: limit-0 containers, 5-min staleness,
duplicate `--log.level`, node_exporter HELP mismatch, PF-MIB not served by NET-SNMP, `sudo -n` false negative.
