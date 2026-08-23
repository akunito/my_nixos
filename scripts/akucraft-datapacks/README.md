# AkuCraft datapacks

Four hand-written datapacks that carry behaviour you cannot infer from the mod
list. Until 2026-08-23 they existed **only** inside prod's world folder, with no
copy anywhere — `grep -r akuportal` over this repo returned nothing.

| Directory | Deployed as | What it does |
|---|---|---|
| `slowtime/` | `akucraft-slowtime.zip` | Days last 3x. Closed-loop virtual clock, and the night-skip the frontier needs because vanilla's cannot move a Multiworld clock. |
| `portals/` | `akucraft-portals/` | The Overworld↔frontier gateway arches, the claim archway pair, and the particle curtains. Carries the traveller's own non-sitting pets. |
| `soulbound-dimfix/` | `akucraft-soulbound-dimfix.zip` | Overrides one function of ly-soulbound-enchantment so items captured off-Overworld come back. |
| `tools/` | `akucraft-tools/` | Item modifiers the admin commands call. No automatic behaviour. |

Deploy, and check for drift, with:

```
./scripts/sync-akucraft-datapacks.py --target prod            # diff, writes nothing
./scripts/sync-akucraft-datapacks.py --target prod --push     # apply, then /reload
./scripts/sync-akucraft-datapacks.py --target prod --pull     # adopt the server's copy
```

Two deploy as `.zip` and two as a directory. That is not cosmetic: a datapack's
enabled/disabled state lives in `level.dat` keyed by file name, so renaming
`akucraft-slowtime.zip` to `akucraft-slowtime` reads as one pack disappearing
and an unrelated one arriving.

These are **not** a nix module. A datapack lives inside the world save, which is
server state, and nix does not manage that.
