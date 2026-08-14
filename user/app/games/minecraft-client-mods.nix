# AkuCraft client mods — declaratively pinned to match the server
#
# The AkuCraft server (VPS_PROD, ~/.homelab/minecraft*/docker-compose.yml)
# pins these exact versions in MODRINTH_PROJECTS. Registry-synced mods
# (supplementaries/moonlight) MUST match between client and server or the
# client is kicked with "Received a registry entry that is unknown to this
# client" (happened 2026-08-03 when an unpinned server auto-upgraded).
#
# Two lists, with different rules:
#   syncedMods — MUST match the server pin. To upgrade: bump here AND in both
#                server compose files, then sync-user.sh on each client
#                machine. Never upgrade only one side.
#   clientMods — client-only (map stack). No server counterpart, no registry
#                entries, safe to bump alone.
#
# Jars are symlinked into the FreesmLauncher instance mods folder, so the
# launcher's mod UI cannot delete/disable them — manage them here instead.
# Client-only mods the user adds by hand (e.g. emi) are left untouched.
#
# Deliberately NOT mirrored here — server-only mods (Modrinth client_side:
# unsupported), which add no registry entries and so never affect the client:
#   easyauth      — offline-account login
#   skinrestorer  — custom skins (/skin set mojang <account>); skins reach
#                   vanilla clients through the normal profile system, so
#                   nothing is needed launcher-side. The optional GUI
#                   companion is skinshuffle, a separate client-side mod.
#
# Gated by systemSettings.freesmLauncherEnable (imported conditionally from
# profiles/personal/home.nix) — same gate as the launcher itself.

{ pkgs, lib, ... }:

let
  # FreesmLauncher instance names that hold an AkuCraft setup.
  instances = [ "1.21.1" ];

  # Mods that MUST match the server pin exactly (they add registry entries).
  # Bump these only together with both server compose files.
  syncedMods = [
    {
      name = "fabric-api-0.116.15+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/Nlt8gI9z/fabric-api-0.116.15%2B1.21.1.jar";
      sha512 = "d5dcf28a05676b1436f7ccce76e2f36495ab058f7c3b6f87a5b5cf5abaaf943ef7f37cd4ce72ff1080965a3d11899cd0bf11121e49c4a651daca20f6338043f7";
    }
    {
      name = "lithium-fabric-0.15.4+mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/N08Z8wog/lithium-fabric-0.15.4%2Bmc1.21.1.jar";
      sha512 = "182064b00e6315e2255b857eaab8eb759e6b042ebd4cc8b855ff0d93f875a5a7188fac49f878d7b29d4ef7e6b6341190ad7f6f6f39f4a6d2c62003468b08e4c6";
    }
    {
      name = "flan-1.21.1-1.12.7-fabric.jar";
      url = "https://cdn.modrinth.com/data/Si383TIH/versions/Dozjx0xr/flan-1.21.1-1.12.7-fabric.jar";
      sha512 = "0124534ac3a578fa77a7a63b34564a87808a4bbb8a7e8eb2514085544031272613b6b4e2217e56314c043bbfc0c51939dad0bdfd8ce614904e0888a504f6ce50";
    }
    {
      name = "supplementaries-fabric-1.21.1-3.8.2.jar";
      url = "https://cdn.modrinth.com/data/fFEIiSDQ/versions/kVl8AtPd/supplementaries-fabric-1.21.1-3.8.2.jar";
      sha512 = "7dd71a9ae467f661af7245aa6863dcf02571cedf9293dce7ada7182da400fc83719bc804751d60a026c5e5c9c0b0f03b8213c5cafa575eb066b520b809b25403";
    }
    {
      name = "moonlight-fabric-1.21.1-3.1.1.jar";
      url = "https://cdn.modrinth.com/data/twkfQtEc/versions/OtIOgMN8/moonlight-fabric-1.21.1-3.1.1.jar";
      sha512 = "2980b164727c6530ef6670dc3a26fe75354b6c41e8831da6f11bf5ef4e6ae4696b8a528f10ec3d1489766d28e3407ec4f6e201c7e61b8b58af811118a640d176";
    }
    # Shield tiers + parry/off-guard mechanics. Adds shield items, hence synced.
    {
      name = "shieldexp-fabric-1.21.1-1.4.1.jar";
      url = "https://cdn.modrinth.com/data/sjxWxSao/versions/XfcwSRkp/shieldexp-fabric-1.21.1-1.4.1.jar";
      sha512 = "b0d8c15d820376524315081b4f8510c5e27a3aa6071d113f7183f9032897363fb04b0933089424441d4fb1526e5e7f7cacab2cc6c07efa97f098351afff068a2";
    }
    # Deterministic enchanting table (pick the enchantment, no gambling).
    # Adds a block, hence synced. Needs puzzles-lib + forge-config-api-port.
    {
      name = "EnchantingInfuser-v21.1.4-1.21.1-Fabric.jar";
      url = "https://cdn.modrinth.com/data/ePv85y52/versions/lBRm6Aii/EnchantingInfuser-v21.1.4-1.21.1-Fabric.jar";
      sha512 = "62311364da8480633f082b1e05fff2503a189c06c54ca9600ebca5b06b3b4c15038e9f25d9eab062ac2ff4e6d938e6856603cf9846666bdb0deaa9563a021552";
    }
    {
      name = "PuzzlesLib-v21.1.52-1.21.1-Fabric.jar";
      url = "https://cdn.modrinth.com/data/QAGBst4M/versions/pqCNhF6A/PuzzlesLib-v21.1.52-1.21.1-Fabric.jar";
      sha512 = "0a2f8266f175caa575574a6c99c17fb0af96e6e8e2dea9cd8d53835a1055b265beaa9a2a7dece806e623d3404df6d3d5673a82197c5862c9514866d64df689d5";
    }
    {
      name = "ForgeConfigAPIPort-v21.1.6-1.21.1-Fabric.jar";
      url = "https://cdn.modrinth.com/data/ohNO6lps/versions/N5qzq0XV/ForgeConfigAPIPort-v21.1.6-1.21.1-Fabric.jar";
      sha512 = "cd9296e78ba969f7aed6e3692aa25eb61c102c79c55ca5f9592576bacaa26feab5d5d48fa30cf07ca852e0f1d42afc4d4558feff69a67b225183d2bc15898cf9";
    }
  ];

  # Client-only mods: the server neither ships nor knows about these, they add
  # no registry entries, and versions need NOT match anyone else's. Players who
  # skip them are unaffected — so these are safe to bump on their own.
  #
  # The map stack: Xaero's draws the minimap/worldmap, and Map Link feeds it
  # live player positions pulled from the server's squaremap web map
  # (http://100.64.0.6:8100). Without Map Link you only see players within
  # render distance, which defeats the point of finding each other.
  # Map Link needs cloth-config; Mod Menu is what exposes its settings screen
  # (that is where the squaremap URL gets entered on first run).
  clientMods = [
    {
      name = "cloth-config-15.0.140-fabric.jar";
      url = "https://cdn.modrinth.com/data/9s6osm5g/versions/HpMb5wGb/cloth-config-15.0.140-fabric.jar";
      sha512 = "1b3f5db4fc1d481704053db9837d530919374bf7518d7cede607360f0348c04fc6347a3a72ccfef355559e1f4aef0b650cd58e5ee79c73b12ff0fc2746797a00";
    }
    {
      name = "modmenu-11.0.4.jar";
      url = "https://cdn.modrinth.com/data/mOgUt4GM/versions/v6Xx3fbU/modmenu-11.0.4.jar";
      sha512 = "45ea8f7e0749bc0eb98900f94486e323f153b199617fa43977b46472e4196ee5a6739f41a1e7f68e270f84a367df5f7f53c2a1f46145ad7d349ede4297895396";
    }
    {
      name = "xaerominimap-fabric-1.21.1-26.4.2.jar";
      url = "https://cdn.modrinth.com/data/1bokaNcj/versions/Tx54V6kI/xaerominimap-fabric-1.21.1-26.4.2.jar";
      sha512 = "153c2273971f2a8b0dbd25a60aff67eb4018b7b8c4786a6d3bdfa97860054200d7d69f634ae2d86f46cc00a66fba53370507bfda7c5f42ed5cc559dbb8d42a59";
    }
    {
      name = "xaeroworldmap-fabric-1.21.1-1.44.2.jar";
      url = "https://cdn.modrinth.com/data/NcUtCpym/versions/L2nO7ZYD/xaeroworldmap-fabric-1.21.1-1.44.2.jar";
      sha512 = "991c8745dda265d9a669271a0f72873a2df1592265ca65338dc4f45cd864d1cf6a17217019b962bf5ebe345110796fea0d7bc602bf8f97cbbae75f33ed3569fc";
    }
    {
      name = "maplink-fabric-4.5.1-1.21-1.21.1.jar";
      url = "https://cdn.modrinth.com/data/kiByZ6gx/versions/nNX7KTbD/maplink-fabric-4.5.1-1.21-1.21.1.jar";
      sha512 = "0788738d3ea30908d7ccefbbf5529afa0aef6aa57b5ae0e55abe7ee0b7eee3bf6d21c5e42e14aff367205efa13174628595d09aec301a8c23af42a26719452b8";
    }
  ];

  modFiles = lib.listToAttrs (lib.concatMap (instance:
    map (mod: {
      name = ".local/share/FreesmLauncher/instances/${instance}/minecraft/mods/${mod.name}";
      value = {
        source = pkgs.fetchurl { inherit (mod) url sha512; };
        # Replace the previously hand-copied jars on first activation.
        force = true;
      };
    }) (syncedMods ++ clientMods)) instances);
in
{
  home.file = modFiles;
}
