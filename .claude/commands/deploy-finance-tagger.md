# Deploy Finance Tagger

Full pipeline: commit, push, deploy NixOS config, sync app files, rebuild container, and commit to homelab repo.

## Prerequisites

- Changes to `templates/finance-tagger/` are ready in the working tree
- VPS is reachable via Tailscale (100.64.0.6, port 56777)
- SSH agent forwarding available (`ssh -A`)

## Steps

### 1. Commit and push in .dotfiles (local)

Stage only finance-tagger related files (and any other changed files the user mentions):

```bash
git add templates/finance-tagger/
# Also stage any related files (e.g., nix config changes) if present
git status
```

Commit with a descriptive message following the repo's `feat(finance):` / `fix(finance):` convention.

```bash
git commit -m "feat(finance): <description>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push origin main
```

### 2. Deploy NixOS config to VPS

Only needed if nix files changed (e.g., homelab-docker.nix, VPS_PROD-config.nix). Skip if only app code changed.

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

### 3. Sync app files to ~/.homelab and rebuild container

Copy ALL app files from the dotfiles template to the live homelab directory, then rebuild:

```bash
ssh -A -p 56777 akunito@100.64.0.6 bash -c '
  # Sync template files to homelab (preserves .env which is managed by NixOS)
  cp ~/.dotfiles/templates/finance-tagger/app.py ~/.homelab/finance-tagger/app.py
  cp ~/.dotfiles/templates/finance-tagger/Dockerfile ~/.homelab/finance-tagger/Dockerfile
  cp ~/.dotfiles/templates/finance-tagger/docker-compose.yml ~/.homelab/finance-tagger/docker-compose.yml
  cp -r ~/.dotfiles/templates/finance-tagger/templates/* ~/.homelab/finance-tagger/templates/
  cp -r ~/.dotfiles/templates/finance-tagger/static/* ~/.homelab/finance-tagger/static/
  # Do NOT copy .env — it is managed by NixOS activation scripts

  # Rebuild and recreate the container
  cd ~/.homelab/finance-tagger
  docker compose up -d --build --force-recreate
'
```

### 4. Commit in ~/.homelab on VPS

The homelab repo tracks service configs. `.env` files are git-crypt encrypted, safe to commit.

```bash
ssh -A -p 56777 akunito@100.64.0.6 bash -c '
  cd ~/.homelab
  git add finance-tagger/
  git status --short
  git commit -m "update finance-tagger app files

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
  git push origin main
'
```

### 5. Verify

```bash
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://127.0.0.1:8190/health"
```

Expected: `{"status":"ok"}`

## Important Notes

- **NEVER copy `.env`** to homelab — it contains credentials managed by NixOS activation scripts (`homelab-docker.nix`)
- **`.env` IS committed** in homelab repo but encrypted via git-crypt — this is safe
- If `revolut-export.js` changed, also copy it: `cp ~/.dotfiles/templates/finance-tagger/revolut-export.js ~/.homelab/finance-tagger/`
- If only app code changed (no nix changes), skip step 2 entirely to save time
- The container healthcheck runs every 30s — give it a moment after rebuild
