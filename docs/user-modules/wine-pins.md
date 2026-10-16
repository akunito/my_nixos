---
id: user-modules.wine-pins
summary: Pinned Wine and GE-Proton builds (pins 1-5) installed on DESK next to the gaming Wine without shadowing it, from the flakes akunito/wine-pins (public) and akunito/wine-pin1 (private).
tags: [wine, proton, ge-proton, umu, gaming, mods, pinning, wine-driver-bridge, user-modules]
related_files:
  - user/app/wine-pins/wine-pins.nix
  - user/app/games/games-heavy.nix
  - profiles/personal/home.nix
  - flake.nix
key_files:
  - user/app/wine-pins/wine-pins.nix
activation_hints:
  - If running a mod or project on a fixed Wine/GE-Proton version, or touching wpinN/wineN commands
date: 2026-10-16
status: published
---

# Wine pins

Frozen Wine/GE-Proton versions for mods and projects, installed **in parallel** with the gaming Wine. The gaming Wine (`pkgs.wineWow64Packages.stagingFull` in `user/app/games/games-heavy.nix`, nixpkgs-stable) keeps updating with this flake; the pins move only when their rev is edited in their own repo. Nothing in the gaming stack (Lutris, Bottles, Steam, umu, `wine` on PATH) is touched.

## Pins

| Pin | Wine | GE-Proton | nixpkgs rev | Repo | For |
|---|---|---|---|---|---|
| 1 | staging 10.20 (same store path as the gaming Wine on 2026-10-16) | GE-Proton10-33 | 25.11 `b6018f8` | `akunito/wine-pin1` (**private**) | a private project |
| 2 | staging 11.19 | — | unstable `7fd4004` | `akunito/wine-pins` | wine-driver-bridge (Claude) |
| 3 | 11.19 vanilla, no staging | — | unstable `7fd4004` | `akunito/wine-pins` | wine-driver-bridge (Claude) |
| 4 | 10.0 stable | GE-Proton10-33 | 25.11 `b6018f8` | `akunito/wine-pins` | mods (conservative) |
| 5 | 11.0 stable | GE-Proton11-7 | unstable `7fd4004` | `akunito/wine-pins` | mods |

All of them come from cache.nixos.org (no compile). Extra store size on DESK: ~6 GB (three Wines + two unpacked GE-Proton builds); pin 1 shares the gaming Wine's path. Every `-ge` pin launches through umu-launcher 1.4.4.

## Commands (pin N)

- `wpinN` / `wpinN --info`: Wine path, patch count, GE-Proton, default prefix.
- `wpinN <tool> [args]`: any tool of that pin (`winecfg`, `wineserver -k`, `winetricks <verb>`, `regedit`). Sets `WINE`/`WINESERVER` for winetricks.
- `wineN <args>`: `wpinN wine <args>`.
- `wpinN-ge <program.exe> [args]` (pins 1, 4, 5): run through GE-Proton with umu-run; `GAMEID` defaults to `umu-default`.

## Flags and wiring

| Flag (userSettings) | Default | DESK | Installs |
|---|---|---|---|
| `winePinsEnable` | false | true | pins 2-5: `inputs.wine-pins.packages.<system>.default` |
| `winePin1Enable` | false | true | pin 1 wrappers `wpin1`, `wine1`, `wpin1-ge` |

- `profiles/personal/home.nix` imports `user/app/wine-pins/wine-pins.nix` when either flag is true. It does not depend on `gamesEnable`.
- `flake.nix` input `wine-pins` is pinned to a rev and must never get `inputs.wine-pins.inputs.*.follows`: that would swap the frozen Wine for ours. Bump: edit the rev, then `nix flake update wine-pins`.
- **Pin 1 is not a flake input, on purpose.** `update.sh` runs `sudo nix flake update`; root has no GitHub credentials, so a private input would break `install.sh -u` on every machine. The `wpin1*` wrappers carry the rev (`winePin1Rev` in the module) and on first use run `nix build git+ssh://git@github.com/akunito/wine-pin1?rev=…` **as the user** (GitHub SSH key) into the GC root `~/.local/state/wine-pins/pin1-<rev>`, then exec from there. Bumping pin 1 = push wine-pin1, edit `winePin1Rev`, deploy.

## Isolation rules (measured 2026-10-16)

- Default prefixes: `~/.local/share/wine-pins/N/prefix` (Wine) and `.../N/prefix-ge` (GE-Proton). Never `~/.wine`. An explicit `WINEPREFIX` wins. Do not point a newer pin at a gaming prefix: Wine upgrades it and an older Wine may not open it again.
- `-ge` runs set `XDG_DATA_HOME=~/.local/share/wine-pins/umu-xdg` for umu, so its Steam Runtime (steamrt3 ~800 MB, steamrt4 ~650 MB, downloaded on first run) never touches the gaming umu in `~/.local/share/umu`.
- umu-launcher 1.3.0 (nixos-25.11) fails to fetch steamrt3: `Digest mismatched: SteamLinuxRuntime_sniper.tar.xz`. That is why every GE pin uses umu 1.4.4 from the unstable rev.
- The current directory and the .exe of a `-ge` run must be under `$HOME`: from a private `/tmp` directory, bwrap fails with `Can't chdir to …`.
- Under GE-Proton a console program's stdout does not reach the terminal; check the exit code or a file it writes.
- `UMU_LOG=debug` dumps the whole environment (API keys included) into the output. Do not use it into a file that persists.

## Forking a pin

`*.patch` files in `patches/pinN/` (wine-pins) or `patches/` (wine-pin1) are applied in name order and rebuild that Wine from source (no cache). Details in each repo's README.

## Where things live

- Public flake: `github.com/akunito/wine-pins` (local clone `~/Projects/wine-pins`), builder `lib.mkPin`.
- Private pin 1: `github.com/akunito/wine-pin1` (local clone `~/Projects/wine-pin1`); its README has the handoff block for a session working on the private project.
- Consumer of pins 2-3: `~/Projects/wine-driver-bridge`.
