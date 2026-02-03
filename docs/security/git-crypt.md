---
id: security.git-crypt
summary: Git-crypt encryption for sensitive configuration data (domains, IPs, credentials)
tags: [git-crypt, secrets, encryption, security, domains, credentials]
related_files: [secrets/*.nix, .gitattributes, profiles/*-config.nix]
---

# Git-Crypt Secrets Management

This repository uses git-crypt to encrypt sensitive configuration data while keeping the rest of the repository public/readable.

## Overview

Git-crypt provides transparent encryption for files in a git repository. Encrypted files appear as binary blobs in git history, but are automatically decrypted when checked out on a machine with the correct key.

### What's Encrypted

- `secrets/domains.nix` - Contains:
  - Domain names (public, local, wildcard)
  - External IP addresses
  - SNMP community strings
  - Email addresses for alerts and ACME

### What's NOT Encrypted

- `secrets/*.template` - Public templates showing the structure without real values
- All other repository files

## File Structure

```
secrets/
├── domains.nix          # ENCRYPTED - real values
└── domains.nix.template # PUBLIC - template for reference
```

## Usage

### Importing Secrets in Profile Configs

Profile configuration files import secrets directly:

```nix
# profiles/LXC_monitoring-config.nix
let
  base = import ./LXC-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = base.systemSettings // {
    # Use secrets for sensitive values
    prometheusSnmpCommunity = secrets.snmpCommunity;
    notificationToEmail = secrets.alertEmail;

    # Use secrets for domain construction
    prometheusBlackboxHttpTargets = [
      { name = "jellyfin"; url = "https://jellyfin.${secrets.localDomain}"; }
      { name = "plane"; url = "https://plane.${secrets.publicDomain}"; }
    ];
  };
}
```

### Importing Secrets in System Modules

System modules can also import secrets:

```nix
# system/app/grafana.nix
{ pkgs, lib, systemSettings, config, ... }:

let
  secrets = import ../../secrets/domains.nix;
in
{
  services.grafana.settings.server.domain = "monitor.${secrets.localDomain}";
}
```

## Key Management

### Key Location

Keys are stored at `~/.git-crypt/`:

```
~/.git-crypt/
├── dotfiles-key       # Key for this repository
└── leftyworkout-key   # Key for other repositories (if any)
```

### Exporting Key for Backup

```bash
# Export key (already done during initialization)
git-crypt export-key ~/.git-crypt/dotfiles-key

# Convert to base64 for secure storage (e.g., Bitwarden)
base64 ~/.git-crypt/dotfiles-key
```

### Unlocking on a New Machine

```bash
# Copy key to new machine
scp ~/.git-crypt/dotfiles-key user@newhost:~/.git-crypt/

# On new machine, unlock the repository
cd ~/.dotfiles
git-crypt unlock ~/.git-crypt/dotfiles-key
```

## .gitattributes Configuration

The encryption patterns are defined in `.gitattributes`:

```gitattributes
# Secrets directory - all .nix files encrypted
secrets/*.nix filter=git-crypt diff=git-crypt

# Exclude template files from encryption (they're public)
secrets/*.template !filter !diff
```

## Verification

### Check Encryption Status

```bash
# Show encryption status of all files
git-crypt status

# Check specific directory
git-crypt status secrets/
```

Expected output:
```
    encrypted: secrets/domains.nix
not encrypted: secrets/domains.nix.template
```

### Verify File is Encrypted in Git

```bash
# Show raw file content (should be binary if encrypted)
git show HEAD:secrets/domains.nix | head -c 50
```

If properly encrypted, this shows binary data starting with `GITCRYPT`.

## Adding New Secrets

1. **Add to `secrets/domains.nix`**:
   ```nix
   {
     # Existing secrets...

     # New secret
     newApiKey = "actual-api-key-value";
   }
   ```

2. **Update the template** (`secrets/domains.nix.template`):
   ```nix
   {
     # Existing templates...

     # New secret
     newApiKey = "your-api-key-here";
   }
   ```

3. **Use in profile/module**:
   ```nix
   let
     secrets = import ../secrets/domains.nix;
   in
   {
     someService.apiKey = secrets.newApiKey;
   }
   ```

## Security Considerations

### Git History

- Old values committed before encryption are still in git history
- Rotating credentials is essential after enabling git-crypt
- Consider using `git filter-repo` or BFG Repo Cleaner for full history purge

### Key Security

- Never commit the git-crypt key to any repository
- Store key backup in a password manager (e.g., Bitwarden)
- Each machine needs the key to decrypt files

### Clone vs Pull

- **Fresh clone**: Files remain encrypted until `git-crypt unlock`
- **Pull on unlocked repo**: Files automatically decrypt

## Troubleshooting

### Files Not Decrypting

```bash
# Check if repo is unlocked
git-crypt status

# If locked, unlock with key
git-crypt unlock ~/.git-crypt/dotfiles-key
```

### "Not a git-crypt repository"

```bash
# Initialize git-crypt (only needed once)
git-crypt init
```

### Key Not Found

```bash
# Verify key exists
ls -la ~/.git-crypt/

# If missing, restore from backup (Bitwarden)
echo "BASE64_KEY_HERE" | base64 -d > ~/.git-crypt/dotfiles-key
chmod 600 ~/.git-crypt/dotfiles-key
```

## Related Documentation

- [Security Guide](../security.md) - Overview of all security features
- [LXC Deployment](../lxc-deployment.md) - Deploying to LXC containers (includes git-crypt setup)
