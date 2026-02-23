# Check Kuma Status

Quick health verification for both Uptime Kuma instances.

## Usage

Run this skill to verify Kuma services are operational and accessible.

---

## Kuma Instances

| Instance | Location | Port | Access |
|----------|----------|------|--------|
| Kuma 1 (Home Watchdog) | TrueNAS Docker | 3001 | Internal only |
| Kuma 2 (Public) | VPS Docker (rootless) | 3001 on 127.0.0.1 | status.akunito.com via Cloudflare Tunnel |

---

## Quick Checks

### Kuma 1 (Home Watchdog - TrueNAS)

```bash
# Check container running
ssh truenas_admin@192.168.20.200 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep kuma"

# Check port listening
ssh truenas_admin@192.168.20.200 "ss -tlnp | grep 3001"

# Check container logs (last 10 lines)
ssh truenas_admin@192.168.20.200 "docker logs uptime-kuma --tail 10"

# Check container resource usage
ssh truenas_admin@192.168.20.200 "docker stats --no-stream uptime-kuma"
```

### Kuma 2 (Public - VPS)

```bash
# Check container running
ssh -A -p 56777 akunito@100.64.0.6 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep kuma"

# Check port listening on localhost
ssh -A -p 56777 akunito@100.64.0.6 "ss -tlnp | grep 3001"

# Internal HTTP check
ssh -A -p 56777 akunito@100.64.0.6 "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001"

# External check via Cloudflare Tunnel
curl -s -o /dev/null -w '%{http_code}' https://status.akunito.com
```

---

## Expected Output

**Healthy state:**
- Kuma 1 (TrueNAS): Container running, port 3001 open
- Kuma 2 (VPS): Container running, port 3001 on localhost, external returns 200

---

## Quick Fixes

### Container Not Running

```bash
# Kuma 1 (TrueNAS)
ssh truenas_admin@192.168.20.200 "docker start uptime-kuma"

# Kuma 2 (VPS) - rootless Docker
ssh -A -p 56777 akunito@100.64.0.6 "docker start uptime-kuma"
```

### High Memory Usage

```bash
# Kuma 1
ssh truenas_admin@192.168.20.200 "docker stats --no-stream uptime-kuma"

# Kuma 2
ssh -A -p 56777 akunito@100.64.0.6 "docker stats --no-stream uptime-kuma"

# Restart if needed
ssh truenas_admin@192.168.20.200 "docker restart uptime-kuma"
ssh -A -p 56777 akunito@100.64.0.6 "docker restart uptime-kuma"
```

### View Recent Logs

```bash
# Kuma 1
ssh truenas_admin@192.168.20.200 "docker logs uptime-kuma --tail 20"

# Kuma 2
ssh -A -p 56777 akunito@100.64.0.6 "docker logs uptime-kuma --tail 20"
```

### Cloudflare Tunnel Not Routing to Kuma 2

If external access fails but the VPS container is running:

```bash
# Check cloudflared container on VPS
ssh -A -p 56777 akunito@100.64.0.6 "docker ps | grep cloudflared"

# Check cloudflared logs
ssh -A -p 56777 akunito@100.64.0.6 "docker logs cloudflared --tail 20"
```

---

## Prometheus Integration Check

```bash
# Verify Prometheus can reach Kuma metrics (if push-based metrics configured)
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test(\"kuma|blackbox\")) | {job: .labels.job, health: .health}'"
```

---

## Output Format

After running checks, report in this format:

```markdown
## Kuma Health Check - [DATE]

### Kuma 1 (Home Watchdog - TrueNAS)
- Container: [UP/DOWN]
- Port 3001: [LISTENING/NOT LISTENING]

### Kuma 2 (Public - VPS)
- Container: [UP/DOWN]
- Localhost 3001: [LISTENING/NOT LISTENING]
- External Access (status.akunito.com): [200/ERROR]

### Issues Found
- [List any problems or "None"]

### Actions Taken
- [List fixes applied or "None needed"]
```
