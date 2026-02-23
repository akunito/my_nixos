# Audit Infrastructure

Comprehensive infrastructure audit skill for gathering current state from VPS, TrueNAS SCALE, and supporting network services.

## Purpose

Use this skill to:
- Gather current service and Docker container state from VPS and TrueNAS
- Verify running services match documentation
- Identify configuration drift
- Update infrastructure documentation with accurate data

**Note:** All akunito LXC containers on Proxmox (192.168.8.82) are SHUT DOWN. Services have been migrated to VPS (Netcup RS 4000 G12) and TrueNAS SCALE.

---

## Audit Steps

### 1. Gather VPS State (Netcup RS 4000 G12)

```bash
# NixOS native services
ssh -A -p 56777 akunito@100.64.0.6 "systemctl status postgresql pgbouncer mysql redis grafana prometheus headscale postfix --no-pager"

# Check all active NixOS services
ssh -A -p 56777 akunito@100.64.0.6 "systemctl list-units --type=service --state=running --no-pager"

# Rootless Docker containers (15 expected)
ssh -A -p 56777 akunito@100.64.0.6 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Docker networks
ssh -A -p 56777 akunito@100.64.0.6 "docker network ls"

# Check listening ports
ssh -A -p 56777 akunito@100.64.0.6 "ss -tlnp | grep -E ':(80|443|3000|3001|5432|6432|3306|6379|9090|9100|51820|56777)'"

# Disk usage
ssh -A -p 56777 akunito@100.64.0.6 "df -h / /var"

# Memory and CPU overview
ssh -A -p 56777 akunito@100.64.0.6 "free -h && echo '---' && uptime"
```

### 2. Gather TrueNAS Docker State (192.168.20.200)

```bash
# List running Docker containers (19 expected)
ssh truenas_admin@192.168.20.200 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Docker networks (check macvlan for NPM)
ssh truenas_admin@192.168.20.200 "docker network ls"

# Check NPM macvlan IP (192.168.20.201)
ssh truenas_admin@192.168.20.200 "docker inspect npm --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'" 2>/dev/null

# Check Tailscale subnet router
ssh truenas_admin@192.168.20.200 "docker ps --filter 'name=tailscale' --format 'table {{.Names}}\t{{.Status}}'"

# Check cloudflared tunnel
ssh truenas_admin@192.168.20.200 "docker ps --filter 'name=cloudflared' --format 'table {{.Names}}\t{{.Status}}'"

# Disk usage (datasets)
ssh truenas_admin@192.168.20.200 "df -h | grep -E '(Filesystem|pool)'"
```

### 3. Check Monitoring (VPS)

```bash
# Prometheus service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active prometheus && echo 'Prometheus: RUNNING' || echo 'Prometheus: STOPPED'"

# Count Prometheus targets
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'"

# List target health
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'"

# Check unhealthy targets
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != \"up\") | {job: .labels.job, instance: .labels.instance, health: .health}'"

# Grafana status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active grafana && echo 'Grafana: RUNNING' || echo 'Grafana: STOPPED'"
```

### 4. Check pfSense (192.168.8.1)

```bash
# SSH to pfSense
ssh admin@192.168.8.1 "pfctl -s info | head -5"

# Check WAN interface
ssh admin@192.168.8.1 "ifconfig igb0 | head -5"

# Check VLAN interfaces
ssh admin@192.168.8.1 "ifconfig ix0.100"
```

### 5. Verify VLAN 100 Storage Network

```bash
# Check DESK bond0.100
ip addr show bond0.100
# Should show 192.168.20.96/24

# Check pfSense ix0.100
ssh admin@192.168.8.1 "ifconfig ix0.100"
# Should show 192.168.20.1/24

# Check TrueNAS bond0
ssh truenas_admin@192.168.20.200 "ip addr show bond0"
# Should show 192.168.20.200/24

# Verify direct L2 paths (no pfSense routing)
ping -c 1 192.168.20.200  # DESK -> TrueNAS
```

### 6. Compare with Monitoring (Kuma + Prometheus)

```bash
# Kuma on TrueNAS (Home Watchdog) - check container running
ssh truenas_admin@192.168.20.200 "docker ps | grep kuma"

# Kuma on VPS (Public status page) - check container running
ssh -A -p 56777 akunito@100.64.0.6 "docker ps | grep kuma"

# External status page
curl -s -o /dev/null -w '%{http_code}' https://status.akunito.com

# Verify Prometheus is scraping all targets
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != \"up\") | {job: .labels.job, instance: .labels.instance, health: .health}'"
```

---

## Documentation Update Checklist

After gathering data, update these files as needed:

1. **`docs/akunito/infrastructure/INFRASTRUCTURE_INTERNAL.md`** (encrypted)
   - Docker container IPs if changed
   - Service ports if changed
   - New/removed containers

2. **`docs/akunito/infrastructure/INFRASTRUCTURE.md`** (public)
   - Service catalog if services added/removed
   - Architecture diagrams if topology changed

3. **`docs/akunito/infrastructure/services/*.md`**
   - Update specific service docs with new info

4. **Regenerate router**:
   ```bash
   python3 scripts/generate_docs_index.py
   ```

---

## Quick Health Check

Run this for a quick overview without detailed audit:

```bash
# Check VPS via Tailscale
echo -n "VPS (Tailscale): "
ssh -A -o ConnectTimeout=5 -p 56777 akunito@100.64.0.6 "echo OK" 2>/dev/null || echo "FAILED"

# Check TrueNAS
echo -n "TrueNAS (192.168.20.200): "
ssh -o ConnectTimeout=5 truenas_admin@192.168.20.200 "echo OK" 2>/dev/null || echo "FAILED"

# Check pfSense
echo -n "pfSense (192.168.8.1): "
ssh -o ConnectTimeout=5 admin@192.168.8.1 "echo OK" 2>/dev/null || echo "FAILED"

# Check DESK
echo -n "DESK (192.168.8.96): "
ping -c 1 -W 2 192.168.8.96 > /dev/null 2>&1 && echo "OK" || echo "FAILED"
```

---

## Output Format

When reporting audit results, use this format:

```markdown
## Infrastructure Audit Report - [DATE]

### Summary
- VPS NixOS services: X running
- VPS Docker containers: Y/15
- TrueNAS Docker containers: Z/19
- Healthy Prometheus targets: N/Total

### Changes Detected
- [List any differences from documentation]

### Recommendations
- [Any suggested updates or fixes]

### Files Updated
- [List docs modified]
```
