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
  #
  # "1.21.1"           the live instance, used for 100.64.0.6:25565
  # "AkuCraft-STAGING" a second instance for the staging server on :25599,
  #                    which runs a throwaway copy of the world. It carries the
  #                    production set PLUS trialMods, so a candidate can be
  #                    tested without touching the instance that connects to the
  #                    live server. Production is a separate server and is
  #                    unaffected until its compose file is changed too.
  #
  # The server address is not managed here; the launcher stores it in binary
  # NBT (servers.dat). Import the .mrpack once and it fills itself in; after
  # that, mod changes arrive through sync-user.sh and the pack only needs
  # re-importing for players who are not on this NixOS config.
  # Live instances get syncedMods + clientMods.
  #
  # "AkuCraft 1.21.1" is the instance imported from the .mrpack. It is listed
  # here because an imported instance goes stale the moment the server gains a
  # mod: on 2026-08-16 it was still on the pre-MCA mod set and the live server
  # kicked it with "Received 307 registry entries that are unknown to this
  # client" (namespace mca). Managing it here keeps it in step without having
  # to delete and re-import, which would also throw away its Xaero waypoints
  # and key bindings.
  instances = [ "1.21.1" "AkuCraft 1.21.1" ];

  # Staging instances additionally get trialMods below, so a candidate can be
  # tested against :25599 without contaminating the instance used for the live
  # server. Declarative on purpose: a hand-imported .mrpack cannot be updated
  # in place (FreeSM only refreshes packs published on Modrinth, by project id -
  # ours is self-hosted, so ManagedPackID is empty), which would mean deleting
  # and re-importing on every change.
  stagingInstances = [ "AkuCraft-STAGING" ];

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

    # --- Character progression (Pufferfish) ---
    # The framework only. The skill TREES are data and live server-side
    # (default-skill-trees), so trees can be rebalanced with /reload without
    # touching the pack or asking anyone to reinstall.
    # Ignoring the skills screen entirely leaves the game exactly as before.
    {
      name = "puffish_skills-0.18.3-1.21-fabric.jar";
      url = "https://cdn.modrinth.com/data/hqQqvaa4/versions/hz4AXzIa/puffish_skills-0.18.3-1.21-fabric.jar";
      sha512 = "4f25fc2cacb58e361bf40e9c80e2c422c6df9c743874019e6b88897f9fc19028d2194ee75866a108475ef2de14053570bf57de45e3c708176914d447ccc7f289";
    }
    {
      name = "puffish_attributes-0.8.3-1.21-fabric.jar";
      url = "https://cdn.modrinth.com/data/FCFcFw09/versions/969uN2vX/puffish_attributes-0.8.3-1.21-fabric.jar";
      sha512 = "a960469a5a33289eb54949cc4538f163ffb3fd94a9bbeb52715073408b2b057ace50e159f11c30adc10df2876416108d1bd9a1f90c49fde501ec38f7fab4ad4a";
    }

    # MCA Reborn - villagers become named NPCs you can talk to, befriend, marry.
    # STABLE 7.7.32, not the betas: every recent build is beta, including one
    # published the day this landed.
    #
    # This is the ONE accepted exception to "everything must be ignorable" -
    # it replaces the villager system outright. Verified on a staging copy of
    # the real world first: existing villagers are NOT deleted and NOT
    # converted (33 vanilla survived intact), and 24 NPCs generated in new
    # villages. So established trading halls keep working; only fresh villages
    # get people. There is no conversion command and allowedSpawnReasons is
    # ['natural','structure'], so disk-loaded villagers are never candidates.
    #
    # ChatAI ships disabled (enableVillagerChatAI = false) and stays that way
    # until MCA has been stable for a while - roadmap phase 9.
    {
      name = "mca-fabric-7.7.32+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/1W98a849/versions/mRrlD2wq/mca-fabric-7.7.32%2B1.21.1.jar";
      sha512 = "63711894458fde2e9889f43f9260a6029ca713a82e738ab19ce619e6849e0fb1597c37dbb28ae97d6f6ebc0022e72be3635dbe1e8f3a974177b0a38dd2a3d782";
    }

    # Explorer's Compass - an in-game finder for every structure on the server.
    # client_side: REQUIRED, unlike the rest of the 2026-08-16 exploration batch
    # (the YUNG's set is server-only and the structure packs are client-optional).
    # It adds an item, so a client without it is kicked with "unknown registry
    # entries" - which is exactly why it has to be in this list and not just in
    # the server compose.
    {
      name = "ExplorersCompass-1.21.1-2.6.0-fabric.jar";
      url = "https://cdn.modrinth.com/data/RV1qfVQ8/versions/qSRKiE4D/ExplorersCompass-1.21.1-2.6.0-fabric.jar";
      sha512 = "134501d97f0c264e609a67a8416dbae7bb5dc7f8e11f82b8130efd7ea0cedc6f3be153f0f61b2c503e5ea1efd4734a12c6edfa922503a94981565adfca8b2402";
    }

    # --- Graduated from staging 2026-08-16, verified in game first ---
    # Artifacts: passive treasure gear, found in chests and never crafted, worn
    # in the Trinkets slots. Bosses of Mass Destruction: four optional endgame
    # bosses whose structures only generate in NEW chunks, spaced far apart in
    # config/cristellib/bosses_of_mass_destruction on both servers.
    {
      name = "artifacts-fabric-13.2.1.jar";
      url = "https://cdn.modrinth.com/data/P0Mu4wcQ/versions/WTnRdeH6/artifacts-fabric-13.2.1.jar";
      sha512 = "3a2efe7f3686118ce7159b68d3ab74de901583d50557ac0d5bef08d806e95ec0bdc1ba21c728b6bf6368b34961709eac6b4a4b93a35bdba53f387880db783795";
    }
    {
      name = "geckolib-fabric-1.21.1-4.9.2.jar";
      url = "https://cdn.modrinth.com/data/8BmcQJ2H/versions/dnJdtm0u/geckolib-fabric-1.21.1-4.9.2.jar";
      sha512 = "2442ebe35e84ab9dc564f059d4003b6a9d2a3f304f02427e8710ad35b3547637f292b2aced021f765c4cbac7c4e9b5043fe9cb84ac85912151cf6d0e9c09696d";
    }
    {
      name = "cardinal-components-api-6.1.3.jar";
      url = "https://cdn.modrinth.com/data/K01OU20C/versions/nLsCe2VD/cardinal-components-api-6.1.3.jar";
      sha512 = "db52fc8c4f14dda723b69eec5a52a693fcb1db72e97114cb530ac8a306d95c13a4234ea54bc6e632134038cb05ba551b5240b9187562fb775a4c7bacb681eff1";
    }
    {
      name = "BOMD-1.10.2-1.21.1.jar";
      url = "https://cdn.modrinth.com/data/du3UfiLL/versions/aSCbUUL1/BOMD-1.10.2-1.21.1.jar";
      sha512 = "64e434b0841d594857191eeed066927f3ade0cd71e39e458fffe3208096398123745de57d1e9fce24842496559cb4614e58f34f85201df093647e20dc41dff8f";
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
    # Sodium - a rewrite of the chunk renderer. This is NOT a graphics mod: it
    # makes the game faster, most of all on weak hardware, and it replaces the
    # vanilla Video Settings with a far richer screen. 0.8.12 specifically,
    # because Supplementaries - which every client already has - breaks with
    # anything below 0.8.12-beta.1.
    #
    # Iris deliberately stays HD-only: the only Iris that accepts Sodium 0.8.x
    # is a beta, and a beta rendering mod does not belong on everyone's machine
    # when the shaders it loads are opt-in anyway.
    {
      name = "sodium-fabric-0.8.12+mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/AANobbMI/versions/KIRFiWG4/sodium-fabric-0.8.12%2Bmc1.21.1.jar";
      sha512 = "8afe411eec65a9f677611ed6390ce656e5a3572f9be473e5dca51ae882a9426a547cd2e8c793278577bb14c17e48158030b11753108926ef33698614bd94ed7f";
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

  # Mods on trial on the staging server only. Move an entry into syncedMods
  # when it graduates to production, and drop it from
  # STAGING_EXTRA_VERSION_IDS in scripts/build-akucraft-pack.py at the same
  # time so the two stay in step.
  # Mods on trial on the staging server only - empty right now. Add an entry
  # here to test a candidate against :25599 without touching the instances that
  # connect to the live server, then move it into syncedMods when it graduates
  # (and add it to the prod compose in the same change).
  trialMods = [
    # Sodium Dynamic Lights - a held torch lights the area. Vanilla has no such
    # thing, and what Diego was seeing came from the Complementary shader's own
    # HELD_LIGHTING_MODE, so it existed only for HD players and only in the main
    # hand. This gives it to everyone, in both hands, without shaders.
    #
    # On trial first because the actual requirement - the OFF hand - is not
    # something either this mod or LambDynamicLights states outright.
    #
    # Note for HD players: its own docs say to turn off first-person lighting
    # when the shader already provides it, or the two stack.
    {
      name = "sodiumdynamiclights-fabric-1.0.10-1.21.1.jar";
      url = "https://cdn.modrinth.com/data/PxQSWIcD/versions/BsbJhy7W/sodiumdynamiclights-fabric-1.0.10-1.21.1.jar";
      sha512 = "395affdb6d2484c071a2905ad247c8c5b13a4fa82f59e1a4c92a043409958f29fab4b4274a2e4aa6d9b55c6fecb4070d4595627e6d309da90bf83ba665fdc84e";
    }
    # Surveyor: a map backend that keeps explored terrain ON THE SERVER and
    # shares it between opt-in groups, across dimensions. Being trialled for
    # the friends/clans map features - position sharing, area sharing, and
    # selling exploration (it copies explored terrain to and from vanilla
    # filled maps at a cartography table, and a filled map is a tradeable item).
    #
    # Its Modrinth metadata lists McQoy as required; the jar does not - McQoy is
    # an optional config UI that would drag in yet_another_config_lib. Only
    # fabric-api is actually needed, and ours is new enough.
    {
      name = "surveyor-1.2.4+1.21.jar";
      url = "https://cdn.modrinth.com/data/4KjqhPc9/versions/egJBsDTn/surveyor-1.2.4%2B1.21.jar";
      sha512 = "3a91efbc596db7192792de069e814aeb3e9e1d771267ea5a5d4371b1311bef26a7f9bd02a28619026c23e4df702d99a1bbaaf732e06179dd4999dbd01aaf920c";
    }
    # The frontend. Client-only, so it never reaches the server jar list.
    {
      name = "antique-atlas-3.1.2+1.21.jar";
      url = "https://cdn.modrinth.com/data/Y5Ve4Ui4/versions/2sDsTAId/antique-atlas-3.1.2%2B1.21.jar";
      sha512 = "e920516b107f009d8a671c4b07a65afc0060a11fe3d2918169eb8320408cb3a71b4bdfa7d58a59ff73d8161a545ba220f4e5d766434d46aa08de14e7fe6368cc";
    }
  ];

  mkFiles = instance: mod: {
    name = ".local/share/FreesmLauncher/instances/${instance}/minecraft/mods/${mod.name}";
    value = {
      source = pkgs.fetchurl { inherit (mod) url sha512; };
      # Replace the previously hand-copied jars on first activation.
      force = true;
    };
  };

  # ---------------------------------------------------------------------------
  # HD instances - the opt-in shader/LOD build, one per server.
  #
  # These are built the OPPOSITE way round to the instances above. They carry
  # AutoModpack and the client-only graphics stack and NOTHING else: the server
  # supplies the actual mod list on first connect. Putting the synced mods here
  # as well would give the client two copies of every jar - one in mods/, one in
  # the automodpack folder - and Fabric refuses to start on a duplicate mod id.
  #
  # 3D Skin Layers is deliberately absent even though it belongs to this stack:
  # it requires fabric-api, which arrives only after the first connect, and
  # Fabric will not launch at all with an unresolved dependency.
  hdInstances = [
    { name = "AkuCraft-HD";         title = "AkuCraft HD";         ip = "100.64.0.6:25565"; }
    { name = "AkuCraft-STAGING-HD"; title = "AkuCraft STAGING HD"; ip = "100.64.0.6:25599"; }
  ];

  hdMods = [
    {
      name = "automodpack-mc1.21.1-fabric-4.0.6.jar";
      url = "https://cdn.modrinth.com/data/k68glP2e/versions/ig9vuxA6/automodpack-mc1.21.1-fabric-4.0.6.jar";
      sha512 = "bd7194b62a99b66dbdd3885ad95516c20e81404bbfacccefb013f867713a9afade507c617ecfc77bf50bcb303977d0849ffad4db3e476ac8938829e641298095";
    }
    # This pair is forced, and not by these three mods alone.
    #
    #   Supplementaries (a SERVER mod we ship)  breaks sodium <0.8.12-beta.1
    #   Sodium 0.8.12                           breaks iris   <1.8.13
    #   Iris 1.8.14-beta.1                      needs  sodium 0.8.x
    #
    # so a beta Iris is the only option, and picking the newest stable release
    # of each in isolation - as this file did at first - produces a set that
    # Fabric refuses to load. Check any change here against the FULL delivered
    # mod list, not just this block.
    {
      name = "sodium-fabric-0.8.12+mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/AANobbMI/versions/KIRFiWG4/sodium-fabric-0.8.12%2Bmc1.21.1.jar";
      sha512 = "8afe411eec65a9f677611ed6390ce656e5a3572f9be473e5dca51ae882a9426a547cd2e8c793278577bb14c17e48158030b11753108926ef33698614bd94ed7f";
    }
    {
      name = "iris-fabric-1.8.14-beta.1+mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/YL57xq9U/versions/bAo1Qhte/iris-fabric-1.8.14-beta.1%2Bmc1.21.1.jar";
      sha512 = "a7fbb629793c52f0be8b049f787cb598879239b1ad8e1de62e103c8b9efff140e3232b93ef1f14e505d262897d8cf9505b1126396429ad4056bff969c8674e52";
    }
    {
      name = "DistantHorizons-3.2.0-b-1.21.1-fabric-neoforge.jar";
      url = "https://cdn.modrinth.com/data/uCdwusMi/versions/ZpKb4kZp/DistantHorizons-3.2.0-b-1.21.1-fabric-neoforge.jar";
      sha512 = "d4199f92f992fbd2c75a3b0e4e81c8a98bee889013f7347f2149ffa62c86748bde22135e9b2c82a10875db94fa576571c661c5ee16d2f567bd8a93d6f255fd22";
    }
  ];

  # Three shaders, all installed, one click apart. The default is UNBOUND, and
  # the distinction matters: by their own authors' descriptions, Reimagined
  # "preserves the elements of Minecraft" while Unbound "transforms the visuals"
  # - same author, same version, same performance. Defaulting to Reimagined made
  # water and lighting look untouched, which is not what an HD pack is for.
  #   Unbound      dramatic light and water, the default
  #   Reimagined   the same shader tuned to stay vanilla-faithful
  #   Bliss        the one from the reference build; heavier, foggier, fantasy
  hdShaderDefault = "ComplementaryUnbound_r5.8.1.zip";
  hdShaders = [
    {
      name = hdShaderDefault;
      url = "https://cdn.modrinth.com/data/R6NEzAwj/versions/VMHXIk50/ComplementaryUnbound_r5.8.1.zip";
      sha512 = "9098dd9e0c18b80f7aba2839cea33ce9a614d97665bbfcac87ccce6e4771667c41602d99088852cb1642ccab20b2ceff9b98af8f2e795bd0d3b90b7c9cbab914";
    }
    {
      name = "ComplementaryReimagined_r5.8.1.zip";
      url = "https://cdn.modrinth.com/data/HVnmMxH1/versions/yCCduG44/ComplementaryReimagined_r5.8.1.zip";
      sha512 = "6bd95215755d25812556ce790d976221f7d677d63112e3e4d3e70b08a62ed41348fa3792dd31bbe720d1e46fe2d525cadb4f66e6358118e1f4aa8e0d11f25c39";
    }
    {
      name = "Bliss_v2.1.2_(Chocapic13_Shaders_edit).zip";
      url = "https://cdn.modrinth.com/data/ZvMtQlho/versions/kC2Y8q1P/Bliss_v2.1.2_%28Chocapic13_Shaders_edit%29.zip";
      sha512 = "dafc60be4980ec40f40edc0f2625cb0976f3c9ce5ed86383146a120480826bb1de70ef5e38b7f1437294ed4d38c6ef3c82ebef0ae4e00b8cee165788c9c18280";
    }
  ];

  hdResourcePack = {
    name = "Better-Leaves-9.5.zip";
    url = "https://cdn.modrinth.com/data/uvpymuxq/versions/XWtayRKd/Better-Leaves-9.5.zip";
    sha512 = "3f50d72bdc7274aa01a7c68d1e8a8f592eddc5e28ad9c60d796815a9892751bc862c0ee0dbed290dd7c4ad994c68d38b8cde02b21c96ecbaab6fe18808fb8750";
  };

  # servers.dat is uncompressed NBT, so it cannot be written with a here-doc.
  # Same layout as scripts/build-akucraft-pack.py - keep the two in step.
  mkServersDat = title: ip: pkgs.runCommand "akucraft-servers.dat" { } ''
    ${pkgs.python3}/bin/python3 - "$out" <<'PY'
    import struct, sys
    def s(x):
        b = x.encode("utf-8")
        return struct.pack(">H", len(b)) + b
    out  = b"\x0a" + s("") + b"\x09" + s("servers") + b"\x0a" + struct.pack(">i", 1)
    out += b"\x08" + s("ip") + s("${ip}")
    out += b"\x08" + s("name") + s("${title}")
    out += b"\x01" + s("hidden") + b"\x00" + b"\x00" + b"\x00"
    open(sys.argv[1], "wb").write(out)
    PY
  '';

  # A FreesmLauncher instance is only listed if it has these two files, so a
  # purely declarative instance has to provide them - importing the .mrpack by
  # hand is exactly the step we are removing.
  # Mirrors byte-for-byte what the launcher itself writes for an imported
  # Fabric 1.21.1 instance. The component ORDER and the cachedRequires links
  # matter: a hand-written file missing org.lwjgl3 makes FreesmLauncher fail
  # with "Couldn't load the instance profile".
  mmcPack = pkgs.writeText "mmc-pack.json" (builtins.toJSON {
    formatVersion = 1;
    components = [
      { uid = "org.lwjgl3"; version = "3.3.3"; cachedName = "LWJGL 3";
        cachedVersion = "3.3.3"; cachedVolatile = true; dependencyOnly = true; }
      { uid = "net.minecraft"; version = "1.21.1"; cachedName = "Minecraft";
        cachedVersion = "1.21.1"; important = true;
        cachedRequires = [ { uid = "org.lwjgl3"; suggests = "3.3.3"; } ]; }
      { uid = "net.fabricmc.intermediary"; version = "1.21.1";
        cachedName = "Intermediary Mappings"; cachedVersion = "1.21.1";
        cachedVolatile = true; dependencyOnly = true;
        cachedRequires = [ { uid = "net.minecraft"; equals = "1.21.1"; } ]; }
      { uid = "net.fabricmc.fabric-loader"; version = "0.19.3";
        cachedName = "Fabric Loader"; cachedVersion = "0.19.3";
        cachedRequires = [ { uid = "net.fabricmc.intermediary"; } ]; }
    ];
  });

  # Files the LAUNCHER and the GAME rewrite: instance metadata, the server list,
  # the options, the Iris config. These cannot be home.file symlinks - the store
  # is read-only, and FreesmLauncher rejects the instance outright with
  # "Couldn't load the instance profile" after logging that instance.cfg and
  # mmc-pack.json are "not writable". So nix SEEDS them once and then leaves
  # them alone; changing a shader or a keybind in game has to keep working.
  hdSeed = i:
    let dir = ".local/share/FreesmLauncher/instances/${i.name}"; in [
      { path = "${dir}/instance.cfg"; src = pkgs.writeText "instance.cfg" ''
          [General]
          ConfigVersion=1.3
          InstanceType=OneSix
          name=${i.title}
          iconKey=default
          AutomaticJava=true
          OverrideCommands=false
          OverrideJavaArgs=false
        ''; }
      { path = "${dir}/mmc-pack.json"; src = mmcPack; }
      { path = "${dir}/minecraft/servers.dat"; src = mkServersDat i.title i.ip; }
      # Shaders and the resource pack are switched ON out of the box. A build
      # that installs shaders and leaves them off only generates questions.
      { path = "${dir}/minecraft/config/iris.properties";
        src = pkgs.writeText "iris.properties" ''
          enableShaders=true
          shaderPack=${hdShaderDefault}
        ''; }
      { path = "${dir}/minecraft/options.txt"; src = pkgs.writeText "options.txt" ''
          resourcePacks:["vanilla","file/${hdResourcePack.name}"]
          graphicsMode:2
          renderDistance:12
          simulationDistance:8
        ''; }
    ] ++ map (sh: {
      path = "${dir}/minecraft/shaderpacks/${sh.name}";
      src = pkgs.fetchurl { inherit (sh) url sha512; };
    }) hdShaders
    ++ [{
      path = "${dir}/minecraft/resourcepacks/${hdResourcePack.name}";
      src = pkgs.fetchurl { inherit (hdResourcePack) url sha512; };
    }]
    ++ map (m: {
      path = "${dir}/minecraft/mods/${m.name}";
      src = pkgs.fetchurl { inherit (m) url sha512; };
      # Bumping a version leaves the old jar behind, and two Sodiums will not
      # load. Sweep anything matching the same family but a different name.
      sweep = "${dir}/minecraft/mods";
      keep = m.name;
      family = builtins.head (lib.splitString "-" m.name);
    }) hdMods;

  # NOTHING in an HD instance may be a symlink into the nix store.
  #
  # Two separate failures, both on 2026-08-16. AutoModpack neutralises a
  # duplicate jar by writing a dummy file over it; against the store that fails
  # with "Read-only file system", so it declares the modpack updated and asks
  # for a restart on every launch, forever. And because home.file symlinks
  # point into a single home-manager-files derivation that holds the WHOLE
  # managed tree, AutoModpack's file indexing walked through them and found the
  # mods belonging to the other instances - it tried to dummy a jar from the
  # plain prod instance while running inside the HD one.
  #
  # Seeding copies is safe here in a way it would not be for the synced set:
  # these are client-only cosmetics, so nothing breaks if the launcher's mod UI
  # disables one, whereas disabling a synced mod gets you kicked - which is the
  # whole reason those stay read-only symlinks.

  hdSeedScript = lib.concatMapStringsSep "\n" (f: ''
    ${lib.optionalString (f ? sweep) ''
      for old in "$HOME/${f.sweep}"/${f.family}-*; do
        [ -e "$old" ] || continue
        [ "$(basename "$old")" = "${f.keep}" ] && continue
        rm -f "$old" && echo "removed superseded $(basename "$old")"
      done
    ''}
    if [ ! -f "$HOME/${f.path}" ] || [ -L "$HOME/${f.path}" ]; then
      rm -f "$HOME/${f.path}"
      mkdir -p "$(dirname "$HOME/${f.path}")"
      install -m 644 ${f.src} "$HOME/${f.path}"
      echo "seeded ${f.path}"
    fi
  '') (lib.concatMap hdSeed hdInstances);

  modFiles = lib.listToAttrs (lib.concatMap (instance:
    map (mkFiles instance) (syncedMods ++ clientMods)) instances);

  stagingFiles = lib.listToAttrs (lib.concatMap (instance:
    map (mkFiles instance) (syncedMods ++ clientMods ++ trialMods)) stagingInstances);
in
{
  home.file = modFiles // stagingFiles;

  home.activation.akucraftHdInstances =
    lib.hm.dag.entryAfter [ "writeBoundary" ] hdSeedScript;
}
