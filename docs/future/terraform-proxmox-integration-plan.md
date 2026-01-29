# Terraform Proxmox Integration Plan

**Created:** 2026-01-29
**Status:** Planning / Future Enhancement
**Priority:** Low (current manual workflow is functional)

## Overview

This document explores integrating Terraform with the existing NixOS-based LXC container management on Proxmox. The goal is to make container infrastructure declarative and version-controlled while keeping the existing NixOS configuration architecture intact.

## Current State

### Existing LXC Profiles

- `LXC-base-config.nix` - Base configuration for all LXC containers
- `LXC_HOME-config.nix` - Homelab services (nixosLabaku)
- `LXC_plane-config.nix` - Production plane service (planePROD-nixos)
- `LXC_template-config.nix` - Template for new containers

### Current Workflow

1. Manually create LXC container in Proxmox UI
2. Clone NixOS template or configure from scratch
3. SSH into container
4. Clone dotfiles repo
5. Run `install.sh` with appropriate profile (e.g., `LXC_HOME`)
6. NixOS declaratively manages everything inside the container

### Pain Points

- Manual container creation (not version-controlled)
- No infrastructure state tracking
- Difficult to reproduce environments
- Scaling requires repetitive manual steps
- No documentation of container resource allocation

## What is terraform-provider-proxmox?

A community-maintained Terraform provider that enables infrastructure-as-code management of Proxmox VE resources via the Proxmox API.

**GitHub:** https://github.com/Telmate/terraform-provider-proxmox
**Registry:** https://registry.terraform.io/providers/Telmate/proxmox/latest/docs

### Capabilities

- Create/destroy LXC containers and VMs
- Manage resource allocation (CPU, RAM, storage)
- Configure networking (static IPs, VLANs, bridges)
- Bind mount host directories
- Clone from templates
- Manage VM/container lifecycle (start, stop, shutdown)
- Upload ISO/templates
- Configure cloud-init

## Proposed Architecture

### Separation of Concerns

```
Terraform Layer                 NixOS Layer
(Infrastructure)                (Configuration)
─────────────────────────────────────────────────────
Container creation       →      Package management
CPU/RAM/Storage         →      Services configuration
Networking              →      User environment
Bind mounts             →      Application setup
Lifecycle management    →      System state
```

### Directory Structure

```
.dotfiles/
├── profiles/
│   ├── LXC-base-config.nix          # NixOS configs (UNCHANGED)
│   ├── LXC_HOME-config.nix
│   └── LXC_plane-config.nix
│
├── infrastructure/                   # NEW - Terraform code
│   ├── main.tf                       # Provider configuration
│   ├── variables.tf                  # Shared variables
│   ├── outputs.tf                    # Output values (IPs, VMIDs)
│   ├── terraform.tfvars              # Variable values (gitignored)
│   │
│   ├── templates.tf                  # Template creation/management
│   ├── lxc_home.tf                   # LXC_HOME container definition
│   ├── lxc_plane.tf                  # LXC_plane container definition
│   │
│   └── README.md                     # Usage instructions
│
└── flake.nix                         # Add terraform to devShells
```

### Example Terraform Configuration

#### Provider Setup (main.tf)

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = true  # For self-signed certs
}
```

#### Container Definition (lxc_home.tf)

```hcl
resource "proxmox_lxc" "nixos_home" {
  target_node  = var.proxmox_node
  hostname     = "nixosLabaku"
  vmid         = 100
  ostemplate   = "local:vztmpl/nixos-23.11-default_20231129_amd64.tar.xz"
  password     = var.lxc_root_password
  unprivileged = true
  onboot       = true
  start        = true

  # Resources
  cores   = 4
  memory  = 8192
  swap    = 512

  # Network - static IP matching LXC_HOME-config.nix
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "192.168.8.80/24"
    gw     = "192.168.8.1"
    firewall = false
  }

  # Root filesystem
  rootfs {
    storage = "local-lvm"
    size    = "20G"
  }

  # Bind mounts (matching current Proxmox setup)
  mountpoint {
    key     = "0"
    slot    = 0
    storage = "/mnt/pve/truenas-iscsi/DATA_4TB"
    mp      = "/mnt/DATA_4TB"
    size    = "0G"
  }

  mountpoint {
    key     = "1"
    slot    = 1
    storage = "/mnt/pve/truenas-nfs/media"
    mp      = "/mnt/NFS_media"
    size    = "0G"
  }

  # SSH keys for initial access
  ssh_public_keys = <<-EOT
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com
  EOT

  # Lifecycle - prevent accidental destruction
  lifecycle {
    prevent_destroy = true
  }
}
```

#### Variables (variables.tf)

```hcl
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://192.168.8.100:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "API Token ID (user@realm!token)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "lxc_root_password" {
  description = "Root password for LXC containers"
  type        = string
  sensitive   = true
}
```

#### Variable Values (terraform.tfvars - GITIGNORED)

```hcl
proxmox_api_token_id     = "root@pam!terraform"
proxmox_api_token_secret = "your-secret-token-here"
lxc_root_password        = "your-secure-password"
```

### Integration with Flake

```nix
# flake.nix
{
  outputs = { self, nixpkgs, ... }: {
    devShells = forAllSystems (system: {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          terraform
          # Terraform will download providers automatically
        ];

        shellHook = ''
          echo "Terraform available for infrastructure management"
          echo "cd infrastructure && terraform init"
        '';
      };
    });
  };
}
```

## Workflow

### Initial Setup

```bash
# 1. Enter dev shell
nix develop

# 2. Initialize Terraform
cd infrastructure
terraform init

# 3. Create API token in Proxmox
# Datacenter > Permissions > API Tokens > Add
# User: root@pam, Token ID: terraform
# Privileges: PVEAdmin

# 4. Create terraform.tfvars (gitignored)
cat > terraform.tfvars <<EOF
proxmox_api_token_id     = "root@pam!terraform"
proxmox_api_token_secret = "paste-token-here"
lxc_root_password        = "your-password"
EOF
```

### Creating New Container

```bash
# 1. Plan - see what will be created
terraform plan

# 2. Apply - create infrastructure
terraform apply

# 3. Deploy NixOS configuration
ssh root@192.168.8.80
# Or use ansible/deploy-rs for automation

# On container:
nix-channel --update
git clone https://github.com/akunito/.dotfiles.git /home/akunito/.dotfiles
cd /home/akunito/.dotfiles
./install.sh /home/akunito/.dotfiles LXC_HOME -s -u
```

### Updating Container Resources

```hcl
# Edit lxc_home.tf
resource "proxmox_lxc" "nixos_home" {
  # ...
  cores   = 6  # Changed from 4
  memory  = 16384  # Changed from 8192
  # ...
}
```

```bash
terraform plan   # Review changes
terraform apply  # Apply changes (may require container restart)
```

### Template Workflow

```hcl
# templates.tf
resource "proxmox_lxc" "nixos_base_template" {
  target_node  = "pve"
  hostname     = "nixos-template"
  vmid         = 999
  template     = true  # Mark as template
  ostemplate   = "local:vztmpl/nixos-23.11-default_20231129_amd64.tar.xz"

  # Minimal base configuration
  cores  = 2
  memory = 2048

  rootfs {
    storage = "local-lvm"
    size    = "8G"
  }

  # Pre-configured with dotfiles
  provisioner "remote-exec" {
    inline = [
      "git clone https://github.com/akunito/.dotfiles.git /root/.dotfiles",
      "nix-channel --add https://nixos.org/channels/nixos-unstable nixpkgs-unstable",
      "nix-channel --update",
    ]
  }
}

# Clone from template
resource "proxmox_lxc" "new_service" {
  clone       = proxmox_lxc.nixos_base_template.vmid
  target_node = "pve"
  hostname    = "new-service"
  vmid        = 110

  # Override specific settings
  cores  = 4
  memory = 8192
}
```

## Migration Path (Low Risk)

### Phase 1: Import Existing Infrastructure (SAFE)

**No changes to running containers**

```bash
# 1. Write Terraform configs that describe existing containers
# 2. Import existing resources into Terraform state

terraform import proxmox_lxc.nixos_home pve/lxc/100
terraform import proxmox_lxc.nixos_plane pve/lxc/101

# 3. Verify state matches reality
terraform plan  # Should show "No changes"
```

This brings existing containers under Terraform management without modifications.

### Phase 2: Test with New Container

```bash
# 1. Create test container via Terraform
# infrastructure/lxc_test.tf

# 2. Apply
terraform apply

# 3. Deploy NixOS config
ssh root@test-container
cd /home/akunito/.dotfiles
./install.sh /home/akunito/.dotfiles LXC_template -s -u

# 4. Validate everything works

# 5. Destroy test
terraform destroy -target=proxmox_lxc.test
```

### Phase 3: Gradual Migration

For each existing container:

```bash
# 1. Backup container
pct snapshot 100 backup-before-terraform

# 2. Export configuration to Terraform
# (Already done in Phase 1 via import)

# 3. Optional: Recreate container
terraform destroy -target=proxmox_lxc.nixos_home
terraform apply -target=proxmox_lxc.nixos_home

# 4. Redeploy NixOS config
# (Your existing workflow)

# 5. Validate and remove backup snapshot
pct delsnapshot 100 backup-before-terraform
```

**Or simply keep imported containers as-is** - no recreation needed.

## Benefits

### 1. Infrastructure as Code

```bash
# Complete disaster recovery
git clone dotfiles-repo
cd infrastructure
terraform apply  # Recreate all containers
# Deploy NixOS configs to all
```

### 2. Version Control

```bash
git log infrastructure/lxc_home.tf
# See history of resource changes
# When did we upgrade from 4GB to 8GB RAM?
# Who changed the IP address?
```

### 3. Documentation

Terraform configs = living documentation
- No more "how is this container configured?"
- Self-documenting infrastructure
- Easy onboarding for new team members

### 4. Consistency

```hcl
# Define once, reuse pattern
module "nixos_lxc" {
  source = "./modules/nixos-lxc"

  hostname = var.hostname
  vmid     = var.vmid
  # Common settings shared across all containers
}

# Use module
module "service1" {
  source   = "./modules/nixos-lxc"
  hostname = "service1"
  vmid     = 110
}

module "service2" {
  source   = "./modules/nixos-lxc"
  hostname = "service2"
  vmid     = 111
}
```

### 5. Scaling

```hcl
# Need 5 more containers?
variable "web_servers" {
  default = 5
}

resource "proxmox_lxc" "web" {
  count = var.web_servers

  hostname = "web${count.index + 1}"
  vmid     = 200 + count.index
  # ... shared configuration ...
}
```

### 6. Fits Existing Architecture

```
Terraform              →  NixOS Profiles
(New layer)               (Unchanged)
─────────────────────────────────────
infrastructure/        →  profiles/
├── lxc_home.tf       →  ├── LXC_HOME-config.nix
├── lxc_plane.tf      →  ├── LXC_plane-config.nix
└── templates.tf      →  └── LXC-base-config.nix

Managed:                  Managed:
- Container creation      - System packages
- Resources (CPU/RAM)     - Services
- Networking              - Users/groups
- Storage/mounts          - Configuration files
- Lifecycle               - Application setup
```

## Risks & Mitigations

### Low Risks (Manageable)

#### 1. Learning Curve

**Risk:** Need to learn Terraform HCL syntax and provider quirks

**Mitigation:**
- Start with one container (LXC_plane as minimal test case)
- Extensive documentation available
- Provider docs: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
- Community examples widely available

#### 2. State Management

**Risk:** `terraform.tfstate` file is critical - loss means lost track of infrastructure

**Mitigation:**
- Backup state file regularly
- Use remote state backend (S3, Terraform Cloud, Git + encryption)
- `.gitignore` sensitive state data
- Document state recovery procedures

Example remote state:
```hcl
# main.tf
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "proxmox/terraform.tfstate"
    region = "us-east-1"
  }
}
```

#### 3. Provider Limitations

**Risk:** Community-maintained provider, not official from Proxmox

**Mitigation:**
- Pin provider version to avoid breaking changes
- Test upgrades in non-production first
- Monitor provider GitHub for known issues
- Contribute fixes upstream if needed

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.1-rc1"  # Pin specific version
    }
  }
}
```

### Medium Risks

#### 4. State Drift

**Risk:** Manual Proxmox changes bypass Terraform, causing state drift

**Mitigation:**
- Establish discipline: only use Terraform for managed resources
- Separate managed vs. unmanaged resources
- Use `terraform refresh` to detect drift
- Document exceptions (resources managed outside Terraform)

```bash
# Detect drift
terraform plan  # Shows changes needed to match config
```

#### 5. Destruction Risk

**Risk:** `terraform destroy` or typo can delete production infrastructure

**Mitigation:**
- Use `prevent_destroy` lifecycle rule for production
- Separate workspaces for prod/dev
- Require manual approval for destroy operations
- Backup before major changes

```hcl
resource "proxmox_lxc" "production" {
  # ...

  lifecycle {
    prevent_destroy = true  # Cannot destroy without removing this
  }
}
```

```bash
# Workspace separation
terraform workspace new production
terraform workspace new development

# Destroy requires explicit target
terraform destroy -target=proxmox_lxc.specific_resource
```

### What WON'T Break

✅ **NixOS configurations** - Completely independent layer
✅ **Existing containers** - Migration is opt-in, can import without changes
✅ **Proxmox host** - Terraform only uses Proxmox API, no host modifications
✅ **Data** - As long as backups exist before changes
✅ **Current workflow** - Can coexist with manual management

## Alternative: Nix-Native Proxmox Management

If Terraform feels like overkill, create NixOS-native Proxmox management scripts.

### Approach

```nix
# infrastructure/proxmox-containers.nix
{ pkgs, ... }:

{
  proxmox.containers = {
    lxc_home = {
      node = "pve";
      vmid = 100;
      hostname = "nixosLabaku";

      resources = {
        cores = 4;
        memory = 8192;
        swap = 512;
      };

      network = {
        bridge = "vmbr0";
        ip = "192.168.8.80/24";
        gateway = "192.168.8.1";
      };

      storage = {
        rootfs = { storage = "local-lvm"; size = "20G"; };
        mountpoints = {
          mp0 = { source = "/mnt/pve/truenas-iscsi/DATA_4TB"; dest = "/mnt/DATA_4TB"; };
          mp1 = { source = "/mnt/pve/truenas-nfs/media"; dest = "/mnt/NFS_media"; };
        };
      };

      nixosConfig = ../profiles/LXC_HOME-config.nix;
    };

    lxc_plane = {
      node = "pve";
      vmid = 101;
      hostname = "planePROD-nixos";

      resources = {
        cores = 2;
        memory = 2048;
        swap = 512;
      };

      network = {
        bridge = "vmbr0";
        dhcp = true;
      };

      storage = {
        rootfs = { storage = "local-lvm"; size = "10G"; };
      };

      nixosConfig = ../profiles/LXC_plane-config.nix;
    };
  };
}
```

### Generate Deployment Scripts

```nix
# infrastructure/generate-pct-commands.nix
{ pkgs, config, ... }:

let
  containerConfig = import ./proxmox-containers.nix { inherit pkgs; };

  generatePctCreate = name: cfg: ''
    pct create ${toString cfg.vmid} local:vztmpl/nixos-23.11.tar.xz \
      --hostname ${cfg.hostname} \
      --cores ${toString cfg.resources.cores} \
      --memory ${toString cfg.resources.memory} \
      --net0 name=eth0,bridge=${cfg.network.bridge},ip=${cfg.network.ip} \
      --rootfs ${cfg.storage.rootfs.storage}:${cfg.storage.rootfs.size} \
      ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v:
        "--${k} ${v.source},mp=${v.dest}"
      ) cfg.storage.mountpoints)}
  '';

in {
  # Generate deployment script
  environment.systemPackages = [
    (pkgs.writeScriptBin "deploy-proxmox-containers" ''
      #!/usr/bin/env bash
      set -euo pipefail

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList generatePctCreate containerConfig.proxmox.containers)}
    '')
  ];
}
```

### Benefits of Nix-Native Approach

- No external dependencies (Terraform)
- Fits existing Nix workflow
- Easier to integrate with NixOS modules
- Single language (Nix)
- Simpler for small deployments

### Drawbacks

- Need to implement state tracking manually
- No established ecosystem (Terraform has mature tooling)
- Less community support
- May need to reinvent Terraform features

## Recommendations

### For Current Setup (3-4 containers, stable homelab)

**Start with Nix-native scripts (Option B)**
- Less tooling overhead
- Fits existing architecture seamlessly
- Lower complexity
- Still declarative and version-controlled
- Sufficient for small-scale deployments

### Consider Terraform When

- Planning to scale beyond 10 containers
- Want industry-standard IaC tooling
- Managing multiple Proxmox nodes/clusters
- Need advanced features (HA, automated migrations)
- Team members already know Terraform
- Integration with other Terraform-managed infrastructure

### Hybrid Approach (Recommended for Testing)

1. **Phase 1:** Create Nix scripts for container deployment
2. **Phase 2:** Test Terraform with one container
3. **Phase 3:** Evaluate which approach fits better
4. **Phase 4:** Commit to one approach or maintain hybrid

## Next Steps

### If Choosing Terraform

1. Create `infrastructure/` directory
2. Write Terraform configs for LXC_template (simplest)
3. Test create/destroy cycle
4. Import existing containers
5. Document workflow in infrastructure/README.md
6. Add to flake.nix devShell

### If Choosing Nix-Native

1. Create `infrastructure/proxmox-containers.nix`
2. Generate deployment scripts
3. Test with LXC_template
4. Add error handling and validation
5. Document workflow
6. Consider creating NixOS module for reusability

### Both Approaches

- Update `.gitignore` for secrets
- Document Proxmox API token creation
- Create backup procedures
- Test disaster recovery workflow
- Add to maintenance documentation

## References

### Terraform Provider

- GitHub: https://github.com/Telmate/terraform-provider-proxmox
- Registry: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
- Examples: https://github.com/Telmate/terraform-provider-proxmox/tree/master/examples

### Proxmox API

- API Documentation: https://pve.proxmox.com/pve-docs/api-viewer/
- `pct` man page: https://pve.proxmox.com/pve-docs/pct.1.html

### Related Documentation

- `docs/proxmox-lxc.md` - Current LXC documentation
- `profiles/LXC-base-config.nix` - Base LXC profile
- `docs/profiles.md` - Profile architecture

## Conclusion

Both Terraform and Nix-native approaches can automate Proxmox container management while preserving the existing NixOS configuration architecture. The choice depends on scale, team familiarity, and integration requirements.

For the current 3-4 container homelab setup, **Nix-native scripts** offer simplicity and tight integration. **Terraform** becomes more valuable as infrastructure scales or when industry-standard tooling is preferred.

The existing NixOS configuration layer remains unchanged in both approaches - this is purely an infrastructure provisioning enhancement.
