---
paths:
  - "system/app/plane-tests/**"
  - "system/app/plane*.nix"
  - ".claude/reference/plane-context.md"
---

# Plane Rules

## Deploying Plane (ABSOLUTE RULE)

`plane-deploy` on VPS_PROD is the ONLY way Plane changes, exactly as `install.sh` is for NixOS. Never copy a bundle, edit a file under `~/.homelab/plane*`, or restart the stack by hand to ship a change — it skips the suite that protects every customisation, and prod loses its rollback point.

```bash
ssh -A -p 56777 akunito@100.64.0.6 'plane-deploy --dev-only'   # build + full suite on dev
ssh -A -p 56777 akunito@100.64.0.6 'plane-deploy --yes'        # dev gate, then prod + smoke
ssh -A -p 56777 akunito@100.64.0.6 'plane-deploy --rollback prod'
```

Two rules it enforces, both deliberate: **no fork change reaches prod without tests in the same commit** (`--no-test-check` overrides it, is logged, and goes into the Telegram report), and a red prod smoke rolls back automatically.

## Where things live

- Fork code + specs: `akunito/plane-up` (own repo, own memory — see the registry in the dotfiles memory).
- Test suite, seeds and `plane-deploy`: `system/app/plane-tests/` (`run.sh` is the iteration loop).
- Plan: `docs/akunito/plans/plane-test-suite/`. Ticket workflow + MCP tools: `.claude/reference/plane-context.md`.
- We never take upstream releases: `/plane-security-review`.
