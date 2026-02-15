# Audit Infrastructure

Comprehensive infrastructure audit skill for gathering current state from all LXC containers and updating documentation.

## Purpose

Use this skill to:
- Gather current Docker container state from all LXC containers
- Verify running services match documentation
- Identify configuration drift
- Update infrastructure documentation with accurate data

---

## Audit Steps

### 1. Gather Docker State from LXC_HOME (192.168.8.80)

```bash
# List running containers
ssh akunito@192.168.8.80 "docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Networks}}'"

# List Docker networks
ssh akunito@192.168.8.80 "docker network ls"

# Get homelab network container IPs
ssh akunito@192.168.8.80 "docker network inspect homelab_home-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'"

# Get media network container IPs
ssh akunito@192.168.8.80 "docker network inspect media_mediarr-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'"

# Get UniFi network info
ssh akunito@192.168.8.80 "docker network inspect unifi_unifi_macvlan --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'" 2>/dev/null || echo "UniFi macvlan not found"
```

### 2. Gather NPM Configuration from LXC_proxy (192.168.8.102)

```bash
# Check running containers
ssh akunito@192.168.8.102 "docker ps"

# List NPM proxy host configs
ssh akunito@192.168.8.102 "ls -la ~/npm/data/nginx/proxy_host/"

# Check cloudflared status
ssh akunito@192.168.8.102 "systemctl status cloudflared --no-pager"

# Check certificate status
ssh akunito@192.168.8.102 "ls -la /var/lib/acme/local.akunito.com/ 2>/dev/null || ls -la /mnt/shared-certs/"
```

### 3. Gather Monitoring State from LXC_monitoring (192.168.8.85)

```bash
# Check service status
ssh akunito@192.168.8.85 "systemctl status prometheus grafana --no-pager"

# Count Prometheus targets
ssh akunito@192.168.8.85 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'"

# List target health
ssh akunito@192.168.8.85 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'"
```

### 4. Gather Application Container State

```bash
# LXC_plane
ssh akunito@192.168.8.86 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# LXC_liftcraftTEST
ssh akunito@192.168.8.87 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# LXC_portfolioprod
ssh akunito@192.168.8.88 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# LXC_mailer
ssh akunito@192.168.8.89 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

### 5. Gather Proxmox State (192.168.8.82)

```bash
# List LXC containers
ssh root@192.168.8.82 "pct list"

# Check storage status
ssh root@192.168.8.82 "pvesm status"

# Check bind mounts for LXC_HOME
ssh root@192.168.8.82 "pct config 100 | grep mp"
```

### 6. Gather VPS State (External)

```bash
# Check Docker containers
ssh -p 56777 root@172.26.5.155 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Check WireGuard status
ssh -p 56777 root@172.26.5.155 "wg show"

# Check services
ssh -p 56777 root@172.26.5.155 "systemctl status wireguard-ui-daemon nginx --no-pager"

# List Nginx sites
ssh -p 56777 root@172.26.5.155 "ls -la /etc/nginx/sites-enabled/"

# Check listening ports
ssh -p 56777 root@172.26.5.155 "ss -tlnp | grep -E ':(80|443|3001|5000|51820|56777)'"
```

---

## Cross-Reference Verification

### 7. Verify VLAN 100 Storage Network

```bash
# Check DESK bond0.100
ip addr show bond0.100
# Should show 192.168.20.96/24

# Check Proxmox vmbr10.100
ssh -A root@192.168.8.82 "ip addr show vmbr10.100"
# Should show 192.168.20.82/24

# Check pfSense ix0.100
ssh admin@192.168.8.1 "ifconfig ix0.100"
# Should show 192.168.20.1/24

# Check TrueNAS bond0
ssh truenas_admin@192.168.20.200 "ip addr show bond0"
# Should show 192.168.20.200/24

# Verify direct L2 paths (no pfSense routing)
ping -c 1 192.168.20.200  # DESK → TrueNAS
ssh -A root@192.168.8.82 "ping -c 1 192.168.20.200"  # Proxmox → TrueNAS

# Check all LXC containers bridge to vmbr10 (10G)
ssh -A root@192.168.8.82 "for ct in \$(pct list | tail -n+2 | awk '{print \$1}'); do echo \"CT \$ct: \$(pct config \$ct | grep net0 | grep -o 'bridge=[^ ,]*')\"; done"
```

### 8. Compare with Monitoring

```bash
# Check Uptime Kuma monitors (internal)
curl -s http://192.168.8.89:3001/api/status-page/home | jq '.publicGroupList[].monitorList[].name' 2>/dev/null || echo "Kuma API not accessible without auth"

# Verify Prometheus is scraping all targets
ssh akunito@192.168.8.85 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != \"up\") | {job: .labels.job, instance: .labels.instance, health: .health}'"
```

---

## Documentation Update Checklist

After gathering data, update these files as needed:

1. **`docs/akunito/infrastructure/INFRASTRUCTURE_INTERNAL.md`** (encrypted)
   - Docker network IPs if changed
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
# Check all LXC containers are responding
for ip in 192.168.8.80 192.168.8.102 192.168.8.85 192.168.8.86 192.168.8.87 192.168.8.88 192.168.8.89; do
  echo -n "$ip: "
  ssh -o ConnectTimeout=2 akunito@$ip "echo OK" 2>/dev/null || echo "FAILED"
done

# Check Proxmox
echo -n "192.168.8.82 (Proxmox): "
ssh -o ConnectTimeout=2 root@192.168.8.82 "echo OK" 2>/dev/null || echo "FAILED"

# Check VPS
echo -n "VPS: "
ssh -o ConnectTimeout=5 -p 56777 root@172.26.5.155 "echo OK" 2>/dev/null || echo "FAILED"
```

---

## Output Format

When reporting audit results, use this format:

```markdown
## Infrastructure Audit Report - [DATE]

### Summary
- Total LXC containers: X
- Total Docker containers: Y
- Healthy Prometheus targets: Z/Total

### Changes Detected
- [List any differences from documentation]

### Recommendations
- [Any suggested updates or fixes]

### Files Updated
- [List docs modified]
```
