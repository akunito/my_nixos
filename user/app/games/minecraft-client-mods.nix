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

    # --- Spell Engine RPG stack (optional CONTENT, not a combat rewrite) ---
    # Deliberately WITHOUT Better Combat: that one rewrites melee for
    # everyone, which is exactly the "relearn the game" the group did not
    # want. Spell Engine leaves vanilla combat alone - ignore the spell books
    # and you play as before.
    {
      name = "player-animation-lib-fabric-2.0.4+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/gedNE4y2/versions/CkedfDp3/player-animation-lib-fabric-2.0.4%2B1.21.1.jar";
      sha512 = "14a931f5cf9f1a767c717a2ae65eb1041d3aab1fbb2c90e3f3a18433ed2f7264674fe40b85c136036fa08d2459543394b65e6866e73e8893e823c5ce37dfd086";
    }
    {
      name = "trinkets-3.10.0.jar";
      url = "https://cdn.modrinth.com/data/5aaWibi9/versions/JagCscwi/trinkets-3.10.0.jar";
      sha512 = "3ea846c945a0559696501ff65b373c8ee8fd9b394604e9910b4ed710c3e07cadc674a615a2c3b385951a42253a418201975df951b3100053ed39afadc70221c9";
    }
    {
      name = "spell_power-fabric-1.6.0+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/8ooWzSQP/versions/IyVyrKj8/spell_power-fabric-1.6.0%2B1.21.1.jar";
      sha512 = "ec8578cd965bd9027d81b16944936307c4751e620747e1724f1e9745882196a9641e181d928dd9ae904b89326317581e7286d282ad0614ae3459f2c7e772850c";
    }
    {
      name = "spell_engine-fabric-1.9.16+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/XvoWJaA2/versions/AzuZrwDk/spell_engine-fabric-1.9.16%2B1.21.1.jar";
      sha512 = "635727febae153e1edd42320493d2ced12b19f74f0b9b22b7d2c882b318a90fb7aa4ddad81b0ba4b222d6b3695ac05c7820d85a775845f66d70908d444152e1e";
    }
    {
      name = "structure_pool_api-fabric-1.2.1+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/LrYZi08Q/versions/Y6aBoKEl/structure_pool_api-fabric-1.2.1%2B1.21.1.jar";
      sha512 = "5db479ad64411a36ab8a4be746625cbd67189a9fb56a5853a9715159afe6cd1f8db5216018330f395211b491ae3cba1da80aa1a66f5904aa17bf18518f71fd3e";
    }
    {
      name = "bundle-api-fabric-1.1.0.jar";
      url = "https://cdn.modrinth.com/data/n8QN6Z1a/versions/b87XqtPa/bundle-api-fabric-1.1.0.jar";
      sha512 = "2ce5825b7122e42195ee4b1f984631d7354bb1ce3733ccdaebf332322ddf8c9babff328ca5c7c5da11026c35f1fe4a1414e62b6006e0796128b7f74c2696bad4";
    }
    {
      name = "runes-fabric-1.3.1+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/lP9Yrr1E/versions/PfNFbP8u/runes-fabric-1.3.1%2B1.21.1.jar";
      sha512 = "9224cbaf0eff0d6c7e52269db04fa8f5dfb867ffe414c90e126aa8b77169bca2cb4dd07e54d582ad8b0ed48dc4bc25dfa5b571941a1337c3b4dcc10bd7f63178";
    }
    {
      name = "azurelibarmor-fabric-1.21.1-3.1.3.jar";
      url = "https://cdn.modrinth.com/data/pduQXSbl/versions/ECrTfeJS/azurelibarmor-fabric-1.21.1-3.1.3.jar";
      sha512 = "c7028d4815e108a90f219fe4eda4384b988b3381954bd72806a4f0d30368beb3ed3bf900eb7d56b12f1ba8f4875a0729675e449be6636bf7ec9c9cb872360efc";
    }
    # The three RPG classes: mage / support / martial, chosen to overlap least.
    {
      name = "wizards-fabric-3.0.4+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/NkGaQMDA/versions/IhFI6pgc/wizards-fabric-3.0.4%2B1.21.1.jar";
      sha512 = "170ec859eb3d422e7b42e894cc84aba9429542cb8d1ee2259cda2b17fe4685b7387fd8daab78309147feae805c1027e8700f8daa2d184a4ca309e9d3257df428";
    }
    {
      name = "paladins-fabric-3.0.5+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/FxXkHaLe/versions/I8fuG8YJ/paladins-fabric-3.0.5%2B1.21.1.jar";
      sha512 = "530d275ad5e81e8d0401c220bb87a6d6310bc66206392a06eea743f54618a7a69c902124ec5e33f781b5c026936b08cbf13255dd1dbe852f14fc2d1717587f51";
    }
    {
      name = "rogues-fabric-3.0.4+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/3MKqoGuP/versions/wWFA4lE5/rogues-fabric-3.0.4%2B1.21.1.jar";
      sha512 = "8c883b1105319c1f613811f74388258496cd878b0324e2d92626157c7bbe6adc2a2293230d9ea85cfffd7d0a53e59cebe7ee2ca4128e27961913b514b47285f5";
    }
    # --- Simply Swords + its three libraries (weapon variety) ---
    # fzzy-config drags fabric-language-kotlin onto the CLIENT too; the server
    # already had kotlin for the expanded-* mods.
    {
      name = "fabric-language-kotlin-1.13.13+kotlin.2.4.10.jar";
      url = "https://cdn.modrinth.com/data/Ha28R6CL/versions/bdhiINYC/fabric-language-kotlin-1.13.13%2Bkotlin.2.4.10.jar";
      sha512 = "9a63c35a550b0362b7b25ff045d93709c7b0dae08c89076cba422813fdfb9e5f5dd021ed3afac9f82e74e95b88c249e8f68b240717151540ca3e88cc27fb9c77";
    }
    {
      name = "architectury-13.0.11-fabric.jar";
      url = "https://cdn.modrinth.com/data/lhGA9TYQ/versions/Pzc2FP5K/architectury-13.0.11-fabric.jar";
      sha512 = "53314eb34890b11ad3c06c6f3ba2d01ae1ca756235ce4f0574e4b0544952a2ab3c628c81b521653d6487d62c5dc3055e06fed6367a3a499bafad909512f0c716";
    }
    {
      name = "SimplyTooltips-fabric-0.1.3.jar";
      url = "https://cdn.modrinth.com/data/6avVoBVB/versions/jrFEfRpA/SimplyTooltips-fabric-0.1.3.jar";
      sha512 = "e4e5797491cf05571baa7ea7824c12201283503221ca51fd62ea006aaff465ccd64de73f5b7b977a8a9ba20a47a5d1c0c38d5a8ace17a8545fbb7ac4ae97e47d";
    }
    {
      name = "fzzy_config-0.7.6+1.21.jar";
      url = "https://cdn.modrinth.com/data/hYykXjDp/versions/kOmySYD4/fzzy_config-0.7.6%2B1.21.jar";
      sha512 = "84f4176e371e65c838e7b78a7defdf18cad1fe5ad47dabe2a3fc5a940d900296d8af7a0320fb0c15040e38bf9be98d046f38a93d392a6ecaed71926de5158ddf";
    }
    {
      name = "simplyswords-fabric-1.63.0-1.21.1.jar";
      url = "https://cdn.modrinth.com/data/bK3Ubu9p/versions/gcFhYOoT/simplyswords-fabric-1.63.0-1.21.1.jar";
      sha512 = "95231b5c2ff5cc01e4dae13f82bb5fd2cec9d683c211f8c6e2df498f5763d75c1c1156717be9ba3490623d06b0783bd823ea8614d05694642a4de3c4a78a67dc";
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
    # EMI (item/recipe viewer). Was a hand-copied file for a long time, which
    # meant it was the one mod a mods-folder wipe would NOT restore. Now pinned
    # like the rest, and it ships in the player mod pack too.
    {
      name = "emi-1.1.24+1.21.1+fabric.jar";
      url = "https://cdn.modrinth.com/data/fRiHVvU7/versions/on5GT1qh/emi-1.1.24%2B1.21.1%2Bfabric.jar";
      sha512 = "2680e7b0a93152d4220afdc30a0452c911dc4b5c9ce1db1b7246c21b777bc2a1945fe97c98c09941d31b7478ae357135a1ef51cd3ba92d08dce35202a830b70d";
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
