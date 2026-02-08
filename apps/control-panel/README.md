# NixOS Infrastructure Control Panel

A web-based control panel for managing NixOS dotfiles infrastructure.

## Features

### Phase 1: Docker Container Management
- View all containers across LXC nodes
- Start/Stop/Restart containers
- View container logs (streaming)
- Auto-refresh status

### Phase 2: Infrastructure Control
- Interactive D3.js profile graph
- Proxmox container management
- NixOS deployment (dry-run + deploy)
- Git operations (status, diff, pull)
- Grafana dashboard embedding

### Phase 3: Profile Configuration Editor
- View profile configurations
- Toggle feature flags
- View packages lists
- (Future) Edit settings, duplicate profiles

## Quick Start

```bash
# Build
cargo build --release

# Run with config
CONFIG_PATH=config.toml ./target/release/control-panel
```

## Configuration

Copy `config.example.toml` to `config.toml` and adjust for your environment:

```toml
[server]
host = "0.0.0.0"
port = 3100

[auth]
username = "admin"
password = "your-secure-password"

[ssh]
private_key_path = "/home/user/.ssh/id_ed25519"
default_user = "akunito"

[proxmox]
host = "192.168.8.82"
user = "root"

[dotfiles]
path = "/home/user/.dotfiles"

[[docker_nodes]]
name = "LXC_HOME"
host = "192.168.8.80"
ctid = 100

[[profiles]]
name = "DESK"
type = "desktop"
hostname = "nixosaku"
ip = "192.168.8.96"
```

## NixOS Integration

Enable in your profile:

```nix
# In profile config
systemSettings = {
  controlPanelEnable = true;
  controlPanelPort = 3100;
};
```

Then apply with `nixos-rebuild switch`.

## Security

- HTTP Basic Auth for all endpoints (except /health)
- SSH key authentication for node access
- Local network only (no public exposure recommended)
- Secrets managed via git-crypt

## API Endpoints

### Docker (Phase 1)
- `GET /docker` - Dashboard with all nodes
- `GET /docker/:node` - Container list for node
- `POST /docker/:node/:container/start` - Start container
- `POST /docker/:node/:container/stop` - Stop container
- `POST /docker/:node/:container/restart` - Restart container
- `GET /docker/:node/:container/logs` - Container logs

### Infrastructure (Phase 2)
- `GET /infra` - Profile graph dashboard
- `GET /infra/profile/:id` - Profile details
- `GET /infra/git/status` - Git status
- `GET /infra/git/diff` - Git diff
- `POST /infra/git/pull` - Pull changes
- `POST /infra/deploy/:profile/dry-run` - Validate deployment
- `POST /infra/deploy/:profile` - Deploy to profile
- `GET /monitoring` - Grafana dashboards

### Editor (Phase 3)
- `GET /editor` - Profile list
- `GET /editor/:profile` - Profile editor
- `POST /editor/:profile/toggle/:flag` - Toggle feature flag
- `GET /editor/:profile/json` - Profile as JSON

## Tech Stack

- **Backend**: Rust + Axum
- **Frontend**: htmx + TailwindCSS (CDN)
- **Graphs**: D3.js
- **SSH**: russh
- **Templates**: Inline HTML (no Askama templates for simplicity)
