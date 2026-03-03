# Check Kuma Status

Quick health verification for Uptime Kuma on VPS.

## Usage

Run this skill to verify the Kuma service is operational and accessible.

---

## Instance

| Property | Value |
|----------|-------|
| Location | VPS Docker (rootless) |
| Port | 3001 on 127.0.0.1 |
| Access | status.akunito.com via Cloudflare Tunnel |
| Local | status.local.akunito.com via Tailscale |

---

## Quick Checks

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
- Container running, port 3001 on localhost, external returns 200

---

## Quick Fixes

### Container Not Running

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker start uptime-kuma"
```

### High Memory Usage

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker stats --no-stream uptime-kuma"

# Restart if needed
ssh -A -p 56777 akunito@100.64.0.6 "docker restart uptime-kuma"
```

### View Recent Logs

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker logs uptime-kuma --tail 20"
```

### Cloudflare Tunnel Not Routing

If external access fails but the VPS container is running:

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker ps | grep cloudflared"
ssh -A -p 56777 akunito@100.64.0.6 "docker logs cloudflared --tail 20"
```

---

## Prometheus Integration Check

```bash
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test(\"kuma|blackbox\")) | {job: .labels.job, health: .health}'"
```

---

## Output Format

After running checks, report in this format:

```markdown
## Kuma Health Check - [DATE]

### VPS Kuma (status.akunito.com)
- Container: [UP/DOWN]
- Localhost 3001: [LISTENING/NOT LISTENING]
- External Access (status.akunito.com): [200/ERROR]

### Issues Found
- [List any problems or "None"]

### Actions Taken
- [List fixes applied or "None needed"]
```
