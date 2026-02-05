# Check Kuma Status

Quick health verification for both Uptime Kuma instances.

## Usage

Run this skill to verify Kuma services are operational and accessible.

---

## Quick Checks

### Kuma 1 (Local - LXC_mailer)

```bash
# Check container running
ssh -A akunito@192.168.8.89 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep kuma"

# Check port listening
ssh -A akunito@192.168.8.89 "ss -tlnp | grep 3001"

# Quick API test (no auth needed for status)
curl -s http://192.168.8.89:3001/api/status-page/globalservices | jq '.ok'
```

### Kuma 2 (Public - VPS)

```bash
# Check container running
ssh -A -p 56777 root@172.26.5.155 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep kuma"

# Check nginx proxying
ssh -A -p 56777 root@172.26.5.155 "curl -s -o /dev/null -w '%{http_code}' http://localhost:3001"

# External check
curl -s -o /dev/null -w '%{http_code}' https://status.akunito.com
```

---

## Expected Output

**Healthy state:**
- Kuma 1: Container running, port 3001 open, API returns `true`
- Kuma 2: Container running, nginx 200, external 200

---

## Quick Fixes

### Container Not Running

```bash
# Kuma 1
ssh -A akunito@192.168.8.89 "cd ~/homelab-watcher && docker compose up -d uptime-kuma"

# Kuma 2
ssh -A -p 56777 root@172.26.5.155 "cd /opt/postfix-relay && docker compose up -d uptime-kuma"
```

### High Memory Usage

```bash
# Check stats
ssh -A akunito@192.168.8.89 "docker stats --no-stream uptime-kuma"

# Restart if needed
ssh -A akunito@192.168.8.89 "docker restart uptime-kuma"
```

### View Recent Logs

```bash
# Kuma 1
ssh -A akunito@192.168.8.89 "docker logs uptime-kuma --tail 20"

# Kuma 2
ssh -A -p 56777 root@172.26.5.155 "docker logs uptime-kuma --tail 20"
```

---

## Prometheus Integration Check

```bash
# Verify blackbox probe for Kuma 1
ssh -A akunito@192.168.8.85 "curl -s 'http://localhost:9115/probe?target=http://192.168.8.89:3001&module=http_2xx' | grep probe_success"
```

---

## Output Format

After running checks, report in this format:

```markdown
## Kuma Health Check - [DATE]

### Kuma 1 (Local)
- Container: [UP/DOWN]
- Port 3001: [LISTENING/NOT LISTENING]
- API Response: [OK/FAILED]

### Kuma 2 (Public)
- Container: [UP/DOWN]
- External Access: [200/ERROR]

### Issues Found
- [List any problems or "None"]

### Actions Taken
- [List fixes applied or "None needed"]
```
