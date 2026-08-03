# AkuCraft client mods — declaratively pinned to match the server
#
# The AkuCraft server (VPS_PROD, ~/.homelab/minecraft*/docker-compose.yml)
# pins these exact versions in MODRINTH_PROJECTS. Registry-synced mods
# (supplementaries/moonlight) MUST match between client and server or the
# client is kicked with "Received a registry entry that is unknown to this
# client" (happened 2026-08-03 when an unpinned server auto-upgraded).
#
# To upgrade: bump the version here AND in both server compose files, then
# sync-user.sh on each client machine. Never upgrade only one side.
#
# Jars are symlinked into the FreesmLauncher instance mods folder, so the
# launcher's mod UI cannot delete/disable them — manage them here instead.
# easyauth is server-only and intentionally absent. Client-only mods the
# user adds by hand (e.g. emi) are left untouched.
#
# Gated by systemSettings.freesmLauncherEnable (imported conditionally from
# profiles/personal/home.nix) — same gate as the launcher itself.

{ pkgs, lib, ... }:

let
  # FreesmLauncher instance names that hold an AkuCraft setup.
  instances = [ "1.21.1" ];

  mods = [
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
  ];

  modFiles = lib.listToAttrs (lib.concatMap (instance:
    map (mod: {
      name = ".local/share/FreesmLauncher/instances/${instance}/minecraft/mods/${mod.name}";
      value = {
        source = pkgs.fetchurl { inherit (mod) url sha512; };
        # Replace the previously hand-copied jars on first activation.
        force = true;
      };
    }) mods) instances);
in
{
  home.file = modFiles;
}
