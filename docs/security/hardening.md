---
id: security.hardening
summary: Security hardening guidelines for NixOS homelab infrastructure
tags: [security, hardening, firewall, services, credentials]
related_files: [system/app/*.nix, profiles/*-config.nix, secrets/*.nix]
---

# Security Hardening Guide

Best practices for securing the NixOS homelab infrastructure.

---

## 1. Firewall Configuration

### Principle of Least Privilege

Only open ports that are strictly necessary:

```nix
# Example: Minimal firewall config for LXC container
allowedTCPPorts = [
  22    # SSH (required)
  9100  # Prometheus Node Exporter (monitoring)
  9092  # cAdvisor (if Docker metrics needed)
];
```

### Service-Specific Guidelines

| Service | Required Ports | Notes |
|---------|---------------|-------|
| SSH | 22/tcp | Consider changing default port |
| Node Exporter | 9100/tcp | Restrict to monitoring server IP |
| cAdvisor | 9092/tcp | Only if Docker metrics needed |
| Nginx | 80,443/tcp | Only on proxy/web servers |
| Syncthing | 22000/tcp,udp | Required for sync |

### Macvlan Services

Services using macvlan (like UniFi Controller at 192.168.8.206) do NOT need ports opened in the host firewall - they have their own IP on the LAN.

---

## 2. Service Binding

### Bind to Localhost When Possible

For services only accessed via reverse proxy:

```nix
services.prometheus = {
  listenAddress = "127.0.0.1";  # Not 0.0.0.0
  port = 9090;
};

services.grafana.settings.server = {
  http_addr = "127.0.0.1";
  http_port = 3002;
};
```

### Remote Scraping Services

For Prometheus targets that need remote scraping, use firewall rules instead:

```nix
# In profile config - restrict to monitoring server only
networking.firewall.extraCommands = ''
  iptables -A INPUT -p tcp --dport 9100 -s 192.168.8.85 -j ACCEPT
  iptables -A INPUT -p tcp --dport 9100 -j DROP
'';
```

---

## 3. Credential Management

### Git-Crypt for Secrets

All sensitive values must be stored in `secrets/domains.nix` (encrypted via git-crypt):

```nix
# secrets/domains.nix
{
  publicDomain = "example.com";
  snmpCommunity = "your-snmp-community";
  smtp2goUser = "user@example.com";
  smtp2goPassword = "your-password";
  alertEmail = "alerts@example.com";
}
```

### Usage in Profiles

```nix
let
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = {
    notificationToEmail = secrets.alertEmail;
    prometheusSnmpCommunity = secrets.snmpCommunity;
  };
}
```

### Usage in Modules

```nix
let
  secrets = import ../../secrets/domains.nix;
in
{
  services.grafana.settings.server.domain = "monitor.${secrets.localDomain}";
}
```

### Never Store Secrets In:

- Profile config files (publicly visible)
- Docker-compose.yml files (use .env files with git-crypt)
- Shell scripts
- Comments

---

## 4. IP Whitelisting

### Nginx Location Blocks

For sensitive endpoints, add IP restrictions:

```nix
locations."/" = {
  proxyPass = "http://127.0.0.1:9090";
  extraConfig = ''
    allow 192.168.8.0/24;   # Main LAN
    allow 172.26.5.0/24;    # WireGuard tunnel
    allow 127.0.0.1;        # Localhost
    deny all;
  '';
};
```

### Network Segments

| Network | CIDR | Purpose |
|---------|------|---------|
| Main LAN | 192.168.8.0/24 | Home devices, LXC containers |
| Storage | 192.168.20.0/24 | TrueNAS, NFS |
| Guest | 192.168.9.0/24 | Isolated guest access |
| WireGuard | 172.26.5.0/24 | VPN tunnel |

---

## 5. SSL/TLS Best Practices

### Certificate Management

- Wildcard certs managed by acme.sh on LXC_proxy
- Shared via Proxmox bind mount to other containers
- Let's Encrypt for public-facing services

### Certificate Monitoring

Monitor certificate expiry with Prometheus blackbox exporter:

```nix
prometheusBlackboxTlsTargets = [
  { name = "local_wildcard"; host = "nextcloud.local.example.com"; port = 443; }
];
```

Alert rules are automatically configured:
- Warning: < 14 days until expiry
- Critical: < 7 days until expiry

---

## 6. Docker Security

### Non-Root Containers

Where possible, run containers as non-root:

```yaml
services:
  myservice:
    user: "1000:1000"
    # or
    user: "${PUID}:${PGID}"
```

### Read-Only Root Filesystem

For stateless containers:

```yaml
services:
  myservice:
    read_only: true
    tmpfs:
      - /tmp
      - /run
```

### Resource Limits

Always set resource limits:

```yaml
services:
  myservice:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          memory: 512M
```

---

## 7. SSH Hardening

### Recommended sshd_config Options

```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    X11Forwarding = false;
  };
};
```

### Key-Based Auth Only

- Generate ED25519 keys: `ssh-keygen -t ed25519`
- Never commit private keys
- Use separate keys for different services

---

## 8. Audit Checklist

### Weekly Review

- [ ] Check for failed SSH login attempts
- [ ] Review firewall logs
- [ ] Verify all services running as expected
- [ ] Check certificate expiry alerts

### Monthly Review

- [ ] Review open ports on all containers
- [ ] Audit user accounts and permissions
- [ ] Check for NixOS/package security updates
- [ ] Review Docker container versions

### Quarterly Review

- [ ] Rotate SNMP community strings
- [ ] Rotate SMTP credentials if compromised
- [ ] Review WireGuard peer configurations
- [ ] Test backup restoration

---

## 9. Related Documentation

- [git-crypt.md](./git-crypt.md) - Secrets management
- [incident-response.md](./incident-response.md) - Security incident procedures
- [INFRASTRUCTURE_INTERNAL.md](../infrastructure/INFRASTRUCTURE_INTERNAL.md) - Infrastructure details
