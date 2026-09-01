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

{ pkgs, lib, systemSettings, ... }:

let
  # Four FreesmLauncher instances, and all four are AutoModpack instances:
  # AkuCraft and AkuCraft HD on the live server, plus a Staging pair on :25599
  # which runs a throwaway copy of the world. They are declared in
  # plainInstances and hdInstances further down; nothing here writes jars into
  # them any more.
  #
  # Until 2026-08-19 the two plain ones were the opposite - sixty-five jars
  # symlinked from the store and kept in step by hand - which is why this file
  # still holds the mod lists below. They are no longer materialised anywhere:
  # they exist because scripts/sync-akucraft-automodpack.py parses them out of
  # this file to build the server's allow-list, which decides what every player
  # is allowed to receive.
  #
  # syncedMods   must match the server pin exactly - they add registry entries
  # clientMods   client-only, delivered through host-modpack
  # trialMods    staging only, so a candidate can be tested against :25599
  #              without touching what the live server hands out

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
    # Grindstone: move enchantments onto a book instead of destroying them.
    # It adds no registry entries, so a client without it is never kicked -
    # which is how it stayed server-only for so long. But the LEVEL COST is
    # drawn by a client-side mixin on GrindstoneScreen, and in 4.0.0 the
    # server-side "alternative cost display" is dead code (addLevelCostLore
    # has no callers). Without this jar the price is invisible and a refusal
    # for lack of levels looks exactly like a bug (2026-08-24).
    {
      name = "grind-enchantments-4.0.0+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/WC4UgDcZ/versions/fQ1HXxD4/grind-enchantments-4.0.0%2B1.21.1.jar";
      sha512 = "a6290f8b2a7546d4910389d619937f6e435f731cb206e23baf6888c690ae661d6bca62c26a4af37e26a1e89910c3a9a087ff7a50af27e0643759ad6b4691e263";
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
    # Traveler's Backpack, replacing Vanilla Backpacks on 2026-08-16.
    #
    # Vanilla Backpacks was a datapack in a jar: a backpack was a command_block
    # with components, opening a 27-slot container in which only 3/9/18/40 slots
    # were real and the rest held marker items pinned to a slot index. Inventory
    # Profiles Next sorts those markers out of place, the datapack then ejects
    # the affected slots by summoning a chest_minecart and killing it - which
    # DROPS the items on the ground, where they despawn. Not configurable away:
    # IPN's per-screen exclusions are keyed by Java class, and that container is
    # the same 9x3 class as an ordinary chest, so excluding it would disable
    # sorting in every chest in the game.
    #
    # This one has its own item and its own screen, so there are no markers and
    # nothing depends on slot indices. It adds real registry entries, which is
    # why it belongs here and not in clientMods - every client must match.
    # All three of its required dependencies (fabric-api, cloth-config,
    # cardinal-components) were already installed.
    {
      name = "travelersbackpack-fabric-1.21.1-10.1.38.jar";
      url = "https://cdn.modrinth.com/data/rlloIFEV/versions/5I4utX2T/travelersbackpack-fabric-1.21.1-10.1.38.jar";
      sha512 = "cbe3ba6a35b3d091ba2c6b31649d5bfc08f7e5c43e8400654a42168d9c24a9fe359f0488d45075b8c2d16bb138e03d08ed89a5531a48ca2c9b8b48ac950dd85b";
    }
    # --- Mods that were on both servers but never in this file ---------------
    # These SEVEN all add registry entries, so a client without them is kicked
    # with "Received N registry entries that are unknown to this client". They
    # reached production only because the first version of
    # sync-akucraft-automodpack.py used a deny-list ending in /mods/*.jar, which
    # fails OPEN - anything not explicitly vetoed was shipped, so nobody noticed
    # they were missing here. Production's allow-list is still that hand-made
    # 46-entry list, complete with a literal "DoggyTalentsNext*.jar" glob.
    #
    # The script now builds an ALLOW-list from this file, which fails closed -
    # correct, but it meant staging shipped 38 files and kicked every client on
    # 2026-08-18. Adding them here is the actual fix, and it is what makes a
    # `--target prod` run safe: without it, the next prod sync would have taken
    # these away from everyone.
    {
      name = "DoggyTalentsNext[Fabric]-1.21.1-1.18.63.jar";
      url = "https://cdn.modrinth.com/data/oXgmplvv/versions/t76oZsgc/DoggyTalentsNext%5BFabric%5D-1.21.1-1.18.63.jar";
      sha512 = "bb857a9884223a16c7b1dd2bfec705a1518b919108bf86605e84ff96f49f9f0bdd01cbdc5da563a75e882c0c9b12d48696e9b174ae32e5de443c4e313b1601d7";
    }
    {
      name = "naturalist-2.0.3-fabric-1.21.1.jar";
      url = "https://cdn.modrinth.com/data/F8BQNPWX/versions/DwMaTECx/naturalist-2.0.3-fabric-1.21.1.jar";
      sha512 = "8834d770b768af12486b0db44a538e3f3f0d0e962d5b7873faed7b59cd42fe26d52047b4785c3ca1eb072cabbfed26c7bd111272c16cb5c0ad9b8031c5d96444";
    }
    {
      name = "respawnablepets-1.21-r2.jar";
      url = "https://cdn.modrinth.com/data/gbFe1FWa/versions/DxDhy0br/respawnablepets-1.21-r2.jar";
      sha512 = "076914fc222740c7678b2863549b866ec6f6ff0a94050619329012c5ca735ad32c6f1122dea1e79e9aa3fd997756693f32b398e34ad286057fe60a971e5cbfed";
    }
    {
      name = "smallships-fabric-1.21.1-2.0.0-b2.1.jar";
      url = "https://cdn.modrinth.com/data/rGWEHQrP/versions/BSRcyUiv/smallships-fabric-1.21.1-2.0.0-b2.1.jar";
      sha512 = "130a549cfd92daecf9c4cc7e3c84ff49b2fb547b597752fc1d521ecbe4405d219617ea4b92d5b144aad041ba1aca881242492d7c021eb2c258f6a9407d2acb46";
    }
    # Balm is Hardcore Revival's library, not a mod on its own.
    {
      name = "balm-fabric-1.21.1-21.0.65.jar";
      url = "https://cdn.modrinth.com/data/MBAkmtvl/versions/VynBiUHt/balm-fabric-1.21.1-21.0.65.jar";
      sha512 = "8e1cc12d357e09f8e9401468ab5655a58123fd5602b73b6afa8b623151ea1e704d03c194364f4fbb8f778a47838d139ab197b9dce933e0ac371b89241fd4fe1e";
    }
    {
      name = "hardcorerevival-fabric-1.21.1-21.1.19.jar";
      url = "https://cdn.modrinth.com/data/HqKoXaXz/versions/dXThjEfo/hardcorerevival-fabric-1.21.1-21.1.19.jar";
      sha512 = "c855fde6f20ac8b51035e90d7df734ddd767076103704b65131b5970357620b4ca63be8ff54b18a31875884e1e7271d48fe5e2ea535a518f94590eb94a9cc6d4";
    }
    # The chat tabs. Production also ships /config/chatplus/chatplus-v2.7.0.json
    # to clients - that entry is preserved by the sync script rather than
    # rebuilt, because it is a config file and not a jar.
    {
      name = "chatplus-fabric-2.8.1.jar";
      url = "https://cdn.modrinth.com/data/cJlZ132G/versions/O0ucbFxe/chatplus-fabric-2.8.1.jar";
      sha512 = "c45ae8f9ec44b679a2e1986441d4e6c4dad648ff99f1988d4d0f40b926ea0add375e4fb1b157fe5324cfaf0436b50edbe57a424ce7b972c3ab4b7ce4d6f31b3e";
    }
    # --- Unified chest storage: Tom's Simple Storage + Storage Drawers ---
    # The ask was "one inventory for every chest in my claim, browsable by
    # category". Tom's is the vanilla-style answer: an Inventory Connector
    # merges touching containers into one inventory and a Storage Terminal
    # searches the lot (`@mod`, `#tag`, sort by name/count). No energy, no
    # progression - ignore the blocks and nothing about the game changes.
    #
    # How the connector actually finds chests (read from
    # InventoryConnectorBlockEntity, not from the mod page, because the mod
    # page does not say): a flood fill outwards from the connector that hops
    # ONLY between containers and trims that physically touch, capped at
    # `invConnectorScanRange` (16). It cannot reach through air, so it cannot
    # quietly swallow a neighbour's chests - but that is exactly what the
    # staging test confirmed on 2026-08-18, and Flan does hold: with
    # `lenientBlockEntityCheck: false` it routes every block entity that is not
    # a lectern or a sign through OPENCONTAINER, and `/data get block` proved at
    # runtime that all of these carry one. Tom's also declares `"mixins": []`,
    # so it cannot intercept the Fabric UseBlockCallback that Flan hooks.
    #
    # What it DOES do is reach across a claim border: a connector placed outside
    # a claim, TOUCHING a chest inside it, pulled an item straight out. No
    # player interacts, so Flan never sees it. Adjacency only - the same rig
    # with a three-block air gap pulled nothing - so one empty block at the
    # border closes it, and that rule lives in the Discord guide (/storage)
    # rather than in a config knob that would not have helped.
    #
    # AE2 was the obvious alternative and is not an option: zero Fabric builds
    # for 1.21.1. Refined Storage has one, but needs power and storage disks,
    # which breaks the "ignorable" rule this server is built on.
    {
      name = "toms_storage_fabric-1.21-2.4.1.jar";
      url = "https://cdn.modrinth.com/data/XZNI4Cpy/versions/rfiala5p/toms_storage_fabric-1.21-2.4.1.jar";
      sha512 = "6f139ba00b373164fe7ebcb5677ec035e19fa28b262b5d0d354650964ad6738f4aebb6d783122b8d1cf314033b4333f996c68cc526ac98e3ff64c70326ff39a6";
    }
    # The category half of the ask. Tom's terminal searches and sorts but has
    # no categories; drawers give them physically - each drawer shows its item
    # on the face, so a wall of them IS the category view, and the connector
    # reads them as ordinary inventories. Wants fabric-api (have it) and
    # optionally forge-config-api-port (have that too).
    {
      name = "StorageDrawers-fabric-1.21.1-13.11.4.jar";
      url = "https://cdn.modrinth.com/data/guitPqEi/versions/78LmfH8Z/StorageDrawers-fabric-1.21.1-13.11.4.jar";
      sha512 = "1ec2f81b50708b610d0e7024d067ac630c0f9497307e68e1dc22ee41c6d196f2db3249cad6ab243f3192e73b6a569fb2936a96b9bf61a94ea67a643a5f5b6283";
    }
    # Hybrid Aquatic, graduated 2026-08-20 after a staging trial. 136 sea
    # creatures plus corals, anemones and sponges. Two things to know:
    #
    #   - it duplicates a good part of Naturalist. Both give sharks, jellyfish,
    #     crabs, giant isopods, starfish, piranha, catfish and bass, in two
    #     different art styles, and Naturalist cannot be split.
    #   - its animals CANNOT be confined to the frontier world. Spawns are
    #     injected per biome and both dimensions use the same biome ids, so
    #     they arrive in the lived-in ocean too. Only the decoration is
    #     frontier-only, and that comes free: corals are worldgen, and the
    #     fenced Overworld will never generate another chunk.
    #
    # Its worldgen rides Lithostitched, the same system Terralith uses, and
    # with biomes ON the reefs placed with no worldgen warning of any kind.
    # Biolith comes along for biome placement; lithostitched had to join the
    # client set for the first time, since Hybrid Aquatic declares it as a
    # hard dependency and the allow-list fails closed.
    #
    # A texture pack that replaces vanilla models - Patrix does - must sit at
    # the BOTTOM of the player's selected packs, or its coral_fan geometry is
    # inherited by the mod's 58 coral fans and the reef renders as huge planes
    # through the seabed. Documented in the HD guide.
    {
      name = "[1.21.1-Fabric] Hybrid Aquatic 1.6.9.jar";
      url = "https://cdn.modrinth.com/data/HH4FjUqN/versions/F5POkJG0/%5B1.21.1-Fabric%5D%20Hybrid%20Aquatic%201.6.9.jar";
      sha512 = "5dc6a76776f71ccd19a2913fb56ae128350285fe7e6b140472f6194ef3ef4f020f04f60e233f76309912a1e33fd14d046e4cb629569f8f9507b342a7fc1d7d63";
    }
    {
      # Lithostitched, on the CLIENT. It has always been a server-side worldgen
      # library here, so it was never in the client set - and the allow-list is
      # fail-closed, so the client simply did not get it. Hybrid Aquatic
      # declares it as a hard dependency, and Fabric refused to start with
      # "requires version 1.5.0 or later of lithostitched, which is missing"
      # (2026-08-20). The version must stay identical to the server's, which is
      # why it sits here in syncedMods rather than among the client-only mods.
      name = "lithostitched-1.7.13-fabric-21.1.jar";
      url = "https://cdn.modrinth.com/data/XaDC71GB/versions/JWtSqSeY/lithostitched-1.7.13-fabric-21.1.jar";
      sha512 = "895052dbfdbe65541eb3a0dc12950d803dcfd702872723dcb2c1d842cb12370f18e79b3543ad9e447e6c66caa2d99569329fec412c5645545c6698923f25f5ad";
    }
    {
      name = "biolith-fabric-3.0.14.jar";
      url = "https://cdn.modrinth.com/data/iGEl6Crx/versions/aBinwigO/biolith-fabric-3.0.14.jar";
      sha512 = "3d0f05a9ae4b001f33437cfb789b1fd9d5a90dde1075197f9ea97fe9b5b01505c2936baf748df641b4476cb1bb30ad229926c3afc310800e7bef076186d8fd81";
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
    # Continuity, added 2026-08-19. Two reasons, and the second is the one that
    # matters day to day:
    #   - it is what makes OptiFine-format connected textures work, which every
    #     HD texture pack worth installing uses;
    #   - it ships a built-in "Glass Pane Culling Fix" pack that culls the faces
    #     between adjacent glass panes. That is a real frame-time win wherever
    #     panes are stacked, and it costs nothing anywhere else.
    # Client-only, no registry entries, depends on fabric-api alone (3.0.0 no
    # longer needs Indium). It must NOT also be seeded into an HD instance:
    # AutoModpack delivers it, and a second copy in mods/ is a duplicate mod id
    # that stops Fabric from starting at all.
    {
      name = "continuity-3.0.0+1.21.jar";
      url = "https://cdn.modrinth.com/data/1IjD5062/versions/kSPJ4hQv/continuity-3.0.0%2B1.21.jar";
      sha512 = "3601ddb50f19142c087d32525bc0afcfb5f49a2e7477b6645a98ec191218739fdf3c6ac95cd298e826eb34fc533af43bb0e78c64e51292866ecabade4d14b13a";
    }
    {
      name = "cloth-config-15.0.140-fabric.jar";
      url = "https://cdn.modrinth.com/data/9s6osm5g/versions/HpMb5wGb/cloth-config-15.0.140-fabric.jar";
      sha512 = "1b3f5db4fc1d481704053db9837d530919374bf7518d7cede607360f0348c04fc6347a3a72ccfef355559e1f4aef0b650cd58e5ee79c73b12ff0fc2746797a00";
    }
    # --- Graduated from staging 2026-08-16, after in-game verification ---
    # Sorting keeps artefacts in their Trinkets slots, the torch lights the
    # offhand, and the delivered set audits clean.
    # --- Quality of life, added 2026-08-16 ---
    # All client-only, all verified against the installed set: none of them
    # declares a conflict with anything we run. Deliberately no mod here drags
    # in a new config library - Zoomify and Controlling were dropped for that
    # reason, in favour of Logical Zoom which needs nothing.
    #
    # libIPN is not optional decoration: Inventory Profiles Next requires it.
    {
      name = "libIPN-fabric-1.21.1-6.6.3.jar";
      url = "https://cdn.modrinth.com/data/onSQdWhM/versions/PSscYPRs/libIPN-fabric-1.21.1-6.6.3.jar";
      sha512 = "765991facc85b2cbc5a40c5ddc506da16f18a5c43de7c42757195dbc8d43e09573504602d3695de0054e5a868c6368fca7ad982738f509ba17a68d373532d16c";
    }
    # The actual request: sorting buttons, auto-refill, lockable slots.
    {
      name = "InventoryProfilesNext-fabric-1.21.1-2.2.6.jar";
      url = "https://cdn.modrinth.com/data/O7RBXm3n/versions/h1db7jG7/InventoryProfilesNext-fabric-1.21.1-2.2.6.jar";
      sha512 = "329ba98932110af7905e0108f96aef2750a2cc6a6eec6fdc7c4a6b3682a9886d91b695ecc9677c2a619d829642a1f795dd01c32564f18e0151a861c9e3a158b1";
    }
    # Drag across slots to move or split stacks. Pairs with the above.
    {
      name = "MouseTweaks-fabric-mc1.21-2.26.jar";
      url = "https://cdn.modrinth.com/data/aC3cM3Vq/versions/ylmBQ38A/MouseTweaks-fabric-mc1.21-2.26.jar";
      sha512 = "1744a48a47aedcbf19a0a93f78473cf0221fc4782852dca7fc02685719174664b4f9d95d353fcfc16902ac3815594511ba6d9ab14391f9b7e25ec9b2e777927a";
    }
    # Look at a block or mob and see what it is. With ~80 mods, half of what
    # you find is unfamiliar, so this is worth more here than on a vanilla server.
    {
      name = "Jade-1.21.1-Fabric-15.10.6.jar";
      url = "https://cdn.modrinth.com/data/nvQzSEkH/versions/adpNvTZS/Jade-1.21.1-Fabric-15.10.6.jar";
      sha512 = "fbae1c796368a09c579dd780a1d510fa5ab73f0eca370ddbfe0a9e6ca162e1b806261577306a259773f309dc4938a839b2065c5eef98b2810855c241addf17f5";
    }
    # Shows saturation and what a food actually restores - matters more if we
    # ever turn natural regeneration off in the frontier world.
    {
      name = "appleskin-fabric-mc1.21-3.0.6.jar";
      url = "https://cdn.modrinth.com/data/EsAfCjCV/versions/b5ZiCjAr/appleskin-fabric-mc1.21-3.0.6.jar";
      sha512 = "accbb36b863bdeaaeb001f7552534f3bdf0f27556795cf8e813f9b32e7732450ec5133da5e0ec9b92dc22588c48ffb61577c375f596dc351f15c15ce6a6f4228";
    }
    # A zoom key. Chosen over Zoomify purely because it needs no config library.
    {
      name = "logical_zoom-0.0.26.jar";
      url = "https://cdn.modrinth.com/data/8bOImuGU/versions/8T4BLoiy/logical_zoom-0.0.26.jar";
      sha512 = "3914d15f37fc208496a13e8956988fc8cbe4b7673e39b4835748ff3655267f4f3d99e39ee4926880d562663e354966096e4b1aba65c5c66ded947dd7a28cc1ed";
    }
    # Free frames: skips rendering entities hidden behind blocks. Worth the most
    # here of anywhere, because MCA fills villages with named NPCs.
    {
      name = "entityculling-fabric-1.10.5-mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/NNAgCjsB/versions/hsWvcyFJ/entityculling-fabric-1.10.5-mc1.21.1.jar";
      sha512 = "5072ddbfc8dbbef450cd80b1e4824a9bd9a5e084ac285eea15f92baef47ab2bf4c37991ec68b56cee47c8b29905ca699f79676ae1c6c964cc92632d2761dd21a";
    }
    {
      name = "ImmediatelyFast-Fabric-1.6.11+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/5ZwdcRci/versions/ATB4eNEP/ImmediatelyFast-Fabric-1.6.11%2B1.21.1.jar";
      sha512 = "f80f7d1d046c65795a51f8338c3189d014eb7b7adcab382259c2d1174c196503640ef2e57fea6e89e17bdcb00e3f1847eafe9db1f283c2cd958cb6df28020920";
    }
    # Throttles the frame rate when the window loses focus or is minimised -
    # with Eclipse and Distant Horizons running, an alt-tabbed game otherwise
    # keeps a GPU busy for nothing.
    #
    # This was a jar dropped into the prod instance BY HAND, which is why the
    # Solo instance was born without it: nix seeds what nix declares. Listing
    # it here is what makes it arrive by itself on every instance. The hash is
    # the official Modrinth 3.11.4 release and was verified to match the
    # hand-placed jar byte for byte before it was removed from the instances.
    {
      name = "dynamic-fps-3.11.4+minecraft-1.21.0-fabric.jar";
      url = "https://cdn.modrinth.com/data/LQ3K71Q1/versions/GBH14HiF/dynamic-fps-3.11.4%2Bminecraft-1.21.0-fabric.jar";
      sha512 = "42c7043517889274f2932f257a78d0a67c22f2bebb1385ab4d0ba7936da2163e907d63f22bfeed5126342b568ddf4d7bc576ab6e76401a07d20a4978ba61bf20";
    }
    # Puts each player's face next to their chat messages. Small, but this is a
    # server of six friends, so it earns its place.
    {
      name = "chat_heads-0.15.7-fabric-1.21.jar";
      url = "https://cdn.modrinth.com/data/Wb5oqrBJ/versions/5t3tM2L3/chat_heads-0.15.7-fabric-1.21.jar";
      sha512 = "2d34ad4031fcf9f8cef8e88d3a69ed2c2d8e0ad32c5571f551e82f045a17c20ed896771c9cd731c8183a4a9134141172a4db733684adfb35e789237d30fec0a9";
    }
    # LambDynamicLights - a held torch lights the area, in either hand.
    #
    # NOT Sodium Dynamic Lights, despite the name fitting our stack better:
    # Sodium 0.8.12 declares `sodiumdynamiclights: *`, i.e. it refuses to load
    # alongside ANY version of it, and the client dies at startup. Sodium does
    # not list lambdynlights at all, and Modrinth marks the two dynamic-light
    # mods mutually incompatible - they do the same job.
    #
    # I shipped the wrong one because I checked compatibility with an ad-hoc
    # grep instead of running scripts/audit-akucraft.py, which was written that
    # same afternoon to catch precisely this.
    {
      name = "lambdynamiclights-4.8.10+1.21.1.jar";
      url = "https://cdn.modrinth.com/data/yBW8D80W/versions/DZDOX6ps/lambdynamiclights-4.8.10%2B1.21.1.jar";
      sha512 = "2a8ca94cd56e9e5ed046126f4b03edba2965c8fe76210ebc5ca53bb075832274dce1cb438082fbc2aea268f93986ad17b6231afad7c100359a9185bba517c4f9";
    }
    # Iris rides along with Sodium for everyone, and not because non-HD players
    # need shaders - they get an empty Shader Packs menu and nothing else. It is
    # here because the HD pack CANNOT ship its own copy of Sodium: AutoModpack
    # now delivers Sodium to every client, so a second copy in the HD instance
    # is a duplicate mod id and Fabric refuses to start. Iris hard-depends on
    # Sodium at launch, so if Iris stays HD-local it needs a local Sodium too.
    # Moving both here removes the duplicate instead of relying on AutoModpack
    # noticing and neutralising it - which is the mechanism that produced an
    # infinite "restart your game" loop earlier today.
    {
      name = "iris-fabric-1.8.14-beta.1+mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/YL57xq9U/versions/bAo1Qhte/iris-fabric-1.8.14-beta.1%2Bmc1.21.1.jar";
      sha512 = "a7fbb629793c52f0be8b049f787cb598879239b1ad8e1de62e103c8b9efff140e3232b93ef1f14e505d262897d8cf9505b1126396429ad4056bff969c8674e52";
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
    # Map Link is deliberately gone (2026-08-18). It added a "web map" button
    # that opened BlueMap, and BlueMap moved behind Cloudflare Access when it
    # became admin-only - so every player got an error page instead. It was
    # deleted from both servers' host-modpack folders at the time, but NOT from
    # here, which meant the next sync-akucraft-automodpack.py run put it
    # straight back (it did, on staging, on 2026-08-18). Removing the entry is
    # what actually makes the removal stick. Players read the map at
    # 100.64.0.6:8100/map/ instead.
    # EMI (item/recipe viewer). Was a hand-copied file for a long time, which
    # meant it was the one mod a mods-folder wipe would NOT restore. Now pinned
    # like the rest, and it ships in the player mod pack too.
    {
      name = "emi-1.1.24+1.21.1+fabric.jar";
      url = "https://cdn.modrinth.com/data/fRiHVvU7/versions/on5GT1qh/emi-1.1.24%2B1.21.1%2Bfabric.jar";
      sha512 = "2680e7b0a93152d4220afdc30a0452c911dc4b5c9ce1db1b7246c21b777bc2a1945fe97c98c09941d31b7478ae357135a1ef51cd3ba92d08dce35202a830b70d";
    }

    # Ambience pack, trialled on staging 2026-08-18 and kept for the sound
    # alone: the visual half of that batch (dynamic lights, Effective water,
    # Physics Mod, first-person body, Better Clouds) was rejected. Effective
    # in particular HARD CRASHES against our Sodium 0.8.12 - its bundled Veil
    # library patches a Sodium that no longer exists. Do not re-add it.
    #
    # These four are here rather than only in the server modpack because the
    # non-HD instances carry their own jars and never talk to AutoModpack, so
    # a server-side entry alone would leave them silent. Sound costs no frames.
    {
      name = "sound-physics-remastered-fabric-1.21.1-1.5.1.jar";
      url = "https://cdn.modrinth.com/data/qyVF9oeo/versions/tVu2EZ4u/sound-physics-remastered-fabric-1.21.1-1.5.1.jar";
      sha512 = "72c69678b6afc5ec48027f6e40f7421370dffa1483e23767e0b5f1b36581be652308b33864848e186845df9052f512b79698c69242adb297058cdc3357b64d60";
    }
    {
      name = "PresenceFootsteps-1.11.2+1.21.jar";
      url = "https://cdn.modrinth.com/data/rcTfTZr3/versions/CrvsDgLW/PresenceFootsteps-1.11.2%2B1.21.jar";
      sha512 = "524e5fd9c063d3ee81baaf4dbe553982a906b9b315dffae4aa64332db22a1f2fa0bb13b339c74ac7c5ddf9a8453b6fdaa9e93abac3c8bc1a9a347405e382f1c5";
    }
    # AmbientSounds needs CreativeCore. 81 MB, but it is audio only: no frames.
    {
      name = "AmbientSounds_FABRIC_v6.3.8_mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/fM515JnW/versions/wU311vqz/AmbientSounds_FABRIC_v6.3.8_mc1.21.1.jar";
      sha512 = "d918b7e973be2d3b53cd30d12e02e9f6252e20441ae6694927b050d1b59741946d0f9e48ff558d5a5fc8ab3b454da6305d20ee437ae0378b8367485e90f79f3a";
    }
    {
      name = "CreativeCore_FABRIC_v2.13.39_mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/OsZiaDHq/versions/wZEbqU3j/CreativeCore_FABRIC_v2.13.39_mc1.21.1.jar";
      sha512 = "4360184be94772c098661b1338b38eb03af47a2f57eab490a5e64e9ffa7598c4fbd9e06aa1c45d80f13d538c8322587944d4a0c0b497b069c29d88291ff8ebf7";
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
  # Still on trial: the Surveyor map-sharing stack, pending the two-player test
  # with komi. Everything else from the 2026-08-16 batch graduated below.
  trialMods = [
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
    # SecondBrain: AI NPCs driven by an LLM. Being trialled as the "voice
    # assistant on each player's own model" idea - it carries three backends
    # (Ollama, an OpenAI-compatible endpoint, and Player2) and bundles ollama4j,
    # so it can talk to a model on a player's own machine over Tailscale rather
    # than to anything on the VPS, which has no GPU.
    #
    # The client jar is needed only for the configuration GUI (`/secondbrain`);
    # the mod itself runs server-side. Having the jar is not the same as having
    # an NPC - none exist until somebody creates one - so it is inert for anyone
    # who does not want it. That is what makes it opt-in.
    #
    # Text-to-speech is the catch: the only TTS path in the jar is Player2's
    # API, and Player2 is a cloud service with no Linux build. Voice is
    # unproven; text is not.
    {
      name = "secondbrain-1.21.1-v3.1.7-alpha.jar";
      url = "https://cdn.modrinth.com/data/CfgaDAdq/versions/p7Znfobb/secondbrain-1.21.1-v3.1.7-alpha.jar";
      sha512 = "349e8c84e97550f4391ce4da52e35e66705c93b888280ea2d187fb282f110172fc53443666790346541c378330fa7fda5b33a1fdaf2045a2a08918815d99f161";
    }
  ];

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
  # HD instances also get a different garbage collector. Distant Horizons warns
  # about this in game and it is right to: G1 pauses to collect, and with DH
  # streaming LODs those pauses land as visible stutter. Generational ZGC keeps
  # pauses under a millisecond, which is the whole point on a client - the trade
  # is a little throughput for a lot of smoothness, and a Ryzen with 4 GB of
  # heap can afford it. NOT for the server: it runs Aikar's G1 flags, which are
  # tuned for exactly the opposite priority.
  # The staging port, named once: it is also what marks an instance as the one
  # trials are allowed to land on.
  stagingAddress = "100.64.0.6:25599";
  prodAddress = "100.64.0.6:25565";
  # AkuCraft Solo (:25567) - a PRIVATE hardcore single-player world. It runs a
  # deliberately smaller server-side mod set (78 against prod's ~104: no teams,
  # chat, claims, shops, tpa, AI-NPC, graves or soulbound), so it must NOT
  # share an instance with prod: AutoModpack hands out a different mod set per
  # server and a single instance cannot hold both without being rewritten on
  # every connect.
  #
  # Everything else is a straight copy of the prod HD instance - same
  # mmc-pack, same JVM args, same Patrix pack order, same shader, same
  # AutoModpack jar - because the whole point of the world is that it should
  # look and feel exactly like what we got right on prod.
  soloAddress = "100.64.0.6:25567";
  # AkuCraft Creative (:25566) - three people building, private like solo. Its
  # own instance for the same reason: 82 server mods against solo's 78 and
  # prod's ~104, and AutoModpack hands out a different set per server.
  # En NAS_PROD desde 2026-08-22, no en el VPS. El host del NAS tiene
  # tailscale0 con 100.64.0.1, así que sigue siendo sólo-tailnet.
  #
  # ⚠️ knownHosts de AutoModpack se indexa por HOSTNAME, no por puerto, así que
  # este cambio hace que cada cliente vuelva a pedir el fingerprint una vez y
  # re-descargue el modpack. El fingerprint EN SÍ no cambia
  # (cc08a279…68f733): el certificado viajó con el data/.
  creativeAddress = "100.64.0.1:25566";

  # Which instances this machine gets. Not every machine should hold every
  # server: DESK_A is Aga's, and seeding it an instance pointed at a private
  # single-player world is noise at best. Keyed rather than filtered by
  # hostname, because modules here must never test the hostname (CLAUDE.md).
  #
  # The default in lib/defaults.nix is the PUBLIC pair; a machine opts into a
  # private world explicitly.
  wanted = systemSettings.akucraftInstances;
  forThisMachine = lib.filter (i: lib.elem i.key wanted);

  hdInstances = forThisMachine [
    { key = "prod";     name = "AkuCraft-HD";          title = "AkuCraft HD";          ip = prodAddress; }
    { key = "staging";  name = "AkuCraft-STAGING-HD";  title = "AkuCraft STAGING HD";  ip = stagingAddress; }
    { key = "solo";     name = "AkuCraft-SOLO-HD";     title = "AkuCraft Solo HD";     ip = soloAddress; }
    { key = "creative"; name = "AkuCraft-CREATIVE-HD"; title = "AkuCraft Creative HD"; ip = creativeAddress; }
  ];

  hdMods = [
    {
      name = "automodpack-mc1.21.1-fabric-4.0.6.jar";
      url = "https://cdn.modrinth.com/data/k68glP2e/versions/ig9vuxA6/automodpack-mc1.21.1-fabric-4.0.6.jar";
      sha512 = "bd7194b62a99b66dbdd3885ad95516c20e81404bbfacccefb013f867713a9afade507c617ecfc77bf50bcb303977d0849ffad4db3e476ac8938829e641298095";
    }
    {
      name = "DistantHorizons-3.2.0-b-1.21.1-fabric-neoforge.jar";
      url = "https://cdn.modrinth.com/data/uCdwusMi/versions/ZpKb4kZp/DistantHorizons-3.2.0-b-1.21.1-fabric-neoforge.jar";
      sha512 = "d4199f92f992fbd2c75a3b0e4e81c8a98bee889013f7347f2149ffa62c86748bde22135e9b2c82a10875db94fa576571c661c5ee16d2f567bd8a93d6f255fd22";
    }
    # What Patrix actually needs to render as designed. It ships FIVE
    # OptiFine-format feature sets and Minecraft understands none of them on
    # its own:
    #
    #   ctm   25198 files  -> Continuity            (in clientMods, everyone)
    #   cem      78 models -> Entity Model Features  <- these two
    #   random  114 files  -> Entity Texture Features
    #   anim     11 files  -> Animatica              (not installed; 11 files)
    #   colors  color.properties -> Colormatic       (not installed)
    #
    # Without EMF the game draws Patrix's 32x entity texture on the VANILLA
    # model, and the UV layout belongs to the .jem model that is being ignored -
    # which is why the witch's hat came out as a flat purple plane through her
    # head (2026-08-20). 78 entities are affected, from allay to zombified
    # piglin, and 1193 entity textures come from the pack.
    #
    # EMF requires ETF, so both. Client-only, no registry entries. The cost is
    # per VISIBLE entity, not per world: nothing alone in a cave, noticeable in
    # a mob farm.
    {
      name = "entity_texture_features_1.21-fabric-7.1.jar";
      url = "https://cdn.modrinth.com/data/BVzZfTc1/versions/udcdeUXw/entity_texture_features_1.21-fabric-7.1.jar";
      sha512 = "ee8ef05dab35287e4df9a5fac0f2b6379da217d79756620d9e5243e72f6e9033ada6f677fd520e70c4c655df0c8c808d785f7f14d25af0c00371047311602c40";
    }
    {
      name = "entity_model_features-3.2.4-1.21-fabric.jar";
      url = "https://cdn.modrinth.com/data/4I1XuqiY/versions/NLDNY8vg/entity_model_features-3.2.4-1.21-fabric.jar";
      sha512 = "466bcc2bf542cafde4d308902bce030e3c0ac1719af327f41e6c16833d2fcfedbd6fdebb2ce323fb14e5cdc75fe6f6ff2ebb6f77a53c5d3af1e4c83eff786f0b";
    }
    {
      # Not Enough Animations: eating, drinking, climbing and the rest, shown
      # in third person. Installed DISABLED - the launcher's Mods tab is the
      # switch, one click, per player. Its own config is twenty separate
      # booleans with no master toggle, so shipping it "off" through the config
      # would be twenty settings to keep false forever, and a new option in a
      # future version would arrive on.
      name = "notenoughanimations-fabric-1.12.4-mc1.21.1.jar";
      url = "https://cdn.modrinth.com/data/MPCX6s5C/versions/HyecdWuC/notenoughanimations-fabric-1.12.4-mc1.21.1.jar";
      sha512 = "c5880052f030f6f26b00da5d5fdd4d2efa83174dafb89ec674da8fc9671beaecd1d07a17ab8154b718cdca1a953da827b61ffbd5de62b852191d40b67eddeb83";
      disabled = true;
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
      # Glowing ores, which Reimagined leaves off and Unbound has by default.
      # Complementary gates them on the STYLE rather than on the setting:
      #   #if GLOWING_ORE_MASTER == 2 || SHADER_STYLE == 4 && GLOWING_ORE_MASTER == 1
      # Reimagined is style 1, so its default value of 1 means "off"; 2 is the
      # explicit "always on". Iris reads this from shaderpacks/<pack name>.txt -
      # the pack name includes the .zip, and it is written by Iris itself the
      # moment the player touches that shader's settings screen, which is why
      # this is seeded once and never overwritten.
      settings = { GLOWING_ORE_MASTER = "2"; };
    }
    {
      name = "Bliss_v2.1.2_(Chocapic13_Shaders_edit).zip";
      url = "https://cdn.modrinth.com/data/ZvMtQlho/versions/kC2Y8q1P/Bliss_v2.1.2_%28Chocapic13_Shaders_edit%29.zip";
      sha512 = "dafc60be4980ec40f40edc0f2625cb0976f3c9ce5ed86383146a120480826bb1de70ef5e38b7f1437294ed4d38c6ef3c82ebef0ae4e00b8cee165788c9c18280";
    }
  ];

  # Texture packs. Trialled on staging on 2026-08-19, kept, and now seeded on
  # every instance of the matching kind.
  #
  # Patrix is the spectacular one, and it belongs on the HD build because it is
  # drawn for shaders. It buys its detail with tiling and randomisation rather
  # than resolution: at 32x the texture memory is four times vanilla, against
  # sixty-four for the 128x PBR packs, and it carries no parallax to raymarch
  # per pixel. Its connected textures are an OptiFine-format feature, so it
  # needs Continuity - shipped alongside. Continuity 3.0.0 depends on fabric-api
  # alone, so Indium is no longer part of that deal.
  #
  # Bare Bones is the opposite bet for the plain build: 16x, the same resolution
  # as vanilla, so there is nothing extra to draw. It changes the style, not the
  # cost.
  #
  # Both are seeded but NOT switched on. options.txt already exists on an
  # instance that has been played and the seeder never overwrites one, so the
  # packs sit in the folder until the player ticks them. For a trial that is
  # what you want anyway - judging a pack means toggling it off again.
  # Three rungs of the same ladder, so the comparison is about how much detail
  # is worth how much frame time rather than about one pack in isolation:
  # 32x tiling (Patrix), 64x PBR (Optimum), 128x PBR + parallax (rotrBLOCKS).
  # The two heavy ones want the shader's advanced-materials option ON or their
  # PBR data is ignored and they just look like big flat textures.
  hdPacks = [
    {
      name = "Patrix_1.21_32x_basic.zip";
      url = "https://cdn.modrinth.com/data/olO1TaXd/versions/iBo0eCWB/Patrix_1.21_32x_basic.zip";
      sha512 = "89c948034c2555d6367aefeaad23e7fbcaad0e75915ea3de000d93bfa962b0eecaa8bd71287d70bc28aec27e0cca40bc9430600771160a6583091f928953335a";
    }
    # Optimum Realism 64x was here and the game rejected it in red. Modrinth's
    # version list is not the authority - pack.mcmeta is, and its 4.0.0 declares
    # pack_format 80 with the min_format/max_format pair that only 1.21.9 and
    # later understand. No release of it targets 1.21.1. CHECK pack_format
    # BEFORE ADDING A PACK: 1.21/1.21.1 is 34, or a supported range containing
    # it. Prime's HD declares exactly 34.
    {
      name = "Prime's HD Textures (32x).zip";
      storeName = "primes-hd-textures-32x.zip";
      url = "https://cdn.modrinth.com/data/PTSGmxET/versions/qlT4zvuP/Prime%27s%20HD%20Textures%20%2832x%29.zip";
      sha512 = "576679d0736d9e6b06f786d554a34d3d08bfe1f5f8d22d6c6ca6ac01e5cb8e364942cda651977d78c640c2b1dc1a3e7da47d336d6267512b5a5ee5cf3fed0665";
    }
    {
      name = "rotrBLOCKS V87 3D Foliage 128x.zip";
      storeName = "rotrblocks-v87-3d-foliage-128x.zip";
      url = "https://cdn.modrinth.com/data/A8aBf1Xa/versions/mPNFFuBE/rotrBLOCKS%20V87%20%5B3D%20Foliage%5D%20128x%2026.2-1.13.zip";
      sha512 = "37c0cbac4252044fe3cbdad8d1675926d2b8969e45aacc18ba6796f89ecf34ebd4d692bbce91b24046cf51055a2aca03fedbff793ead1f24379012cbd608037d";
    }
  ];

  plainPacks = [
    {
      name = "Bare Bones 1.21.11.zip";
      storeName = "bare-bones-1.21.11.zip";
      url = "https://cdn.modrinth.com/data/rox3U8B6/versions/jQBWn2Q3/Bare%20Bones%201.21.11.zip";
      sha512 = "268b578d6d34adaa2491572af4cabf65fab94edee00e688f5b4cb4f072c0620c492d58a4442769e6a889cd940cfe3c4a4fe65e5bb422b8e283ad174e32ceefb0";
    }
  ];

  # Shaders on trial, staging HD only - same idea as hdTrialPacks. Graduating
  # one means moving its entry into hdShaders.
  hdTrialShaders = [
    {
      # Rethinking Voxels: voxel-traced coloured lighting, built on
      # Complementary Reimagined, with full Distant Horizons support (14 dh
      # programs). Being a Reimagined derivative it inherits GLOWING_ORE_MASTER
      # and its style-1 default, so ores need the explicit 2 here as well.
      name = "rethinking-voxels_r0.1-beta9.zip";
      url = "https://cdn.modrinth.com/data/kmwfVOoi/versions/cpD4esk9/rethinking-voxels_r0.1-beta9.zip";
      sha512 = "1e32f41e67e527c3c60149677a05b61c6d305e440812e29abba745b8ed304954780ca48d58b834c49835790bc3c4d38f37c893c5cbdfea9edc07b72e1dabd296";
      settings = { GLOWING_ORE_MASTER = "2"; };
    }
  ];

  # Patrix's collateral damage on modded blocks, undone.
  #
  # Patrix redraws 421 vanilla block models, and a vanilla model is also a
  # PARENT: 87 modded models inherit one that Patrix has genuinely moved, then
  # supply their own 16x texture. The shape and the texture disagree and the
  # block comes out deformed - Hybrid Aquatic's coral fans as huge angled
  # planes through the seabed, and the same trap set for Supplementaries'
  # potted plants, its redstone dust and every modded crop.
  #
  # Built by scripts/build-patrix-fix-pack.py, which measures rather than
  # guesses: it compares each Patrix model's bounding box against vanilla and
  # only acts when a face has moved by more than half a pixel. Patrix nudges
  # pressure plates by 0.01 to stop z-fighting; the coral wall fan moves by
  # 2.77. Of the 421, 181 clear that bar and 8 of those are actually inherited
  # by a mod.
  #
  # The fix re-parents the mod's models onto a private copy of the VANILLA
  # shape under our own namespace, so Patrix keeps its 3D corals and pots on
  # vanilla blocks. It touches nothing in the minecraft namespace, so its
  # position in the resource pack order does not matter - unlike Patrix
  # itself, which has to sit on TOP or the packs above it show through.
  #
  # It is committed as a built artifact because it is derived from the mod
  # jars, which only exist after AutoModpack has run. Rebuild it after any
  # change to the synced mod set and bump the -N suffix; the sweep below
  # removes the older copy.
  hdFixPack = {
    name = "AkuCraft-Patrix-fixes-1.zip";
    src = ./assets/AkuCraft-Patrix-fixes-1.zip;
  };

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

  # PLAIN instances - the same AutoModpack build as the HD ones, minus the
  # graphics stack. Since 2026-08-19 there is no other kind.
  #
  # They used to be the opposite: sixty-five jars symlinked in from the store,
  # kept in step by hand through syncedMods and clientMods. That made every
  # server-side mod change a home-manager rebuild on the client, and it drifted
  # the moment anything was added on the server first. Now the instance carries
  # AutoModpack and nothing else, exactly like the one a player imports, so
  # Akunito's client updates through the same path as everybody else's - which
  # also means a break in that path shows up here instead of hiding.
  #
  # The mod lists stay where they are: they are still the source of truth for
  # what the server is allowed to hand out (scripts/sync-akucraft-automodpack.py
  # reads them straight out of this file).
  # Solo and Creative have no plain variant on purpose: both exist to be played
  # with the full graphics stack, which is the whole point of the HD instance.
  plainInstances = forThisMachine [
    { key = "prod";    name = "AkuCraft";         title = "AkuCraft";         ip = prodAddress; }
    { key = "staging"; name = "AkuCraft-STAGING"; title = "AkuCraft Staging"; ip = stagingAddress; }
  ];

  # Candidates on trial: seeded ONLY on the HD instance that points at :25599,
  # so production keeps the set that has already been judged. Graduating one is
  # moving its entry into hdPacks above.
  #
  # Empty right now. Cubic Sun & Moon and Hyper Realistic Sky were here on
  # 2026-08-19 and both were dropped: with a shader running, the shader draws
  # the sky and its own celestial bodies, so the packs did nothing visible even
  # when placed above Patrix. A sky pack is for a game WITHOUT shaders.
  hdTrialPacks = [ ];

  automodpackJar = builtins.head hdMods;

  plainSeed = i:
    let dir = ".local/share/FreesmLauncher/instances/${i.name}"; in [
      { path = "${dir}/instance.cfg"; src = pkgs.writeText "instance.cfg" ''
          [General]
          ConfigVersion=1.3
          InstanceType=OneSix
          name=${i.title}
          iconKey=default
          AutomaticJava=true
          OverrideCommands=false
        ''; }
      { path = "${dir}/mmc-pack.json"; src = mmcPack; }
      { path = "${dir}/minecraft/servers.dat"; src = mkServersDat i.title i.ip; }
      { path = "${dir}/minecraft/mods/${automodpackJar.name}";
        src = pkgs.fetchurl { inherit (automodpackJar) url sha512; }; }
    ] ++ map (pack: {
      path = "${dir}/minecraft/resourcepacks/${pack.name}";
      src = pkgs.fetchurl ({ inherit (pack) url sha512; }
        // lib.optionalAttrs (pack ? storeName) { name = pack.storeName; });
    }) plainPacks;

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
          OverrideJavaArgs=true
          JvmArgs=-XX:+UseZGC -XX:+ZGenerational
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
      # The pack ORDER is the whole configuration, and it is lowest priority
      # first. Patrix has to be at the TOP: anything above it shows through,
      # and Continuity's own "Default Connected Textures" pack was doing
      # exactly that - it ships VANILLA 16x glass, sandstone and bookshelf art
      # and Patrix covers all three itself, so it is left OFF. Only the fix
      # pack goes above Patrix, and only because nothing else may.
      # Better-Leaves is installed but not enabled for the same reason: it
      # carries 11 vanilla-namespace leaf textures at 16x.
      # The FULL options.txt, not the four keys it used to carry.
      #
      # A four-key file meant a new instance was born with vanilla keybinds,
      # vanilla fov and vanilla volume, and lost the two namespaced resource
      # packs on its first launch because the mods providing them had not
      # arrived from AutoModpack yet. AkuCraft-SOLO-HD was created that way on
      # 2026-08-22 and reported as "the graphics are different" - the shader
      # was the visible half; the rest was an entire remapped keyboard.
      #
      # What matters most in here: hotbar 1-9 are UNBOUND so Spell Engine's
      # spell bar can own those keys. Lose that and the RPG stack is unusable
      # without rebinding eleven keys by hand.
      #
      # incompatibleResourcePacks is deliberately empty - it is session state
      # the game rebuilds from whatever mods actually loaded, and the prod list
      # names mods (mca, hardcorerevival, toms_storage) that Solo does not have.
      #
      # The seeder only writes a file that does not exist, so this never
      # overwrites settings anyone has since changed in game.
      { path = "${dir}/minecraft/options.txt"; src = pkgs.writeText "options.txt" ''
          version:3955
          ao:true
          biomeBlendRadius:2
          enableVsync:true
          entityDistanceScaling:1.0
          entityShadows:true
          forceUnicodeFont:false
          japaneseGlyphVariants:false
          fov:0.5
          fovEffectScale:1.0
          darknessEffectScale:1.0
          glintSpeed:0.5
          glintStrength:0.75
          prioritizeChunkUpdates:0
          fullscreen:false
          gamma:0.5
          graphicsMode:1
          guiScale:3
          maxFps:120
          mipmapLevels:4
          narrator:0
          particles:0
          reducedDebugInfo:false
          renderClouds:"true"
          renderDistance:12
          simulationDistance:8
          screenEffectScale:1.0
          soundDevice:""
          autoJump:false
          operatorItemsTab:false
          autoSuggestions:true
          chatColors:true
          chatLinks:true
          chatLinksPrompt:true
          discrete_mouse_scroll:false
          invertYMouse:false
          realmsNotifications:true
          showSubtitles:false
          directionalAudio:true
          touchscreen:false
          bobView:true
          toggleCrouch:false
          toggleSprint:false
          darkMojangStudiosBackground:false
          hideLightningFlashes:false
          hideSplashTexts:false
          mouseSensitivity:0.5
          damageTiltStrength:1.0
          highContrast:false
          narratorHotkey:true
          resourcePacks:["vanilla","fabric","moonlight:merged_pack","continuity:glass_pane_culling_fix","file/${(builtins.head hdPacks).name}","file/${hdFixPack.name}"]
          incompatibleResourcePacks:[]
          lastServer:
          lang:en_us
          chatVisibility:0
          chatOpacity:1.0
          chatLineSpacing:0.0
          textBackgroundOpacity:0.5
          backgroundForChatOnly:true
          hideServerAddress:false
          advancedItemTooltips:false
          pauseOnLostFocus:true
          overrideWidth:0
          overrideHeight:0
          chatHeightFocused:1.0
          chatDelay:0.0
          chatHeightUnfocused:0.4375
          chatScale:1.0
          chatWidth:1.0
          notificationDisplayTime:1.0
          useNativeTransport:true
          mainHand:"right"
          attackIndicator:1
          tutorialStep:none
          mouseWheelSensitivity:1.0
          rawMouseInput:true
          glDebugVerbosity:1
          skipMultiplayerWarning:true
          hideMatchedNames:true
          joinedFirstServer:true
          hideBundleTutorial:false
          syncChunkWrites:false
          showAutosaveIndicator:true
          allowServerListing:true
          onlyShowSecureChat:false
          panoramaScrollSpeed:1.0
          telemetryOptInExtra:false
          onboardAccessibility:false
          menuBackgroundBlurriness:5
          key_key.attack:key.mouse.left
          key_key.use:key.mouse.right
          key_key.forward:key.keyboard.w
          key_key.left:key.keyboard.a
          key_key.back:key.keyboard.s
          key_key.right:key.keyboard.d
          key_key.jump:key.keyboard.space
          key_key.sneak:key.keyboard.left.shift
          key_key.sprint:key.keyboard.left.control
          key_key.drop:key.keyboard.q
          key_key.inventory:key.keyboard.e
          key_key.chat:key.keyboard.t
          key_key.playerlist:key.keyboard.tab
          key_key.pickItem:key.mouse.middle
          key_key.command:key.keyboard.slash
          key_key.socialInteractions:key.keyboard.p
          key_key.screenshot:key.keyboard.f2
          key_key.togglePerspective:key.keyboard.f5
          key_key.smoothCamera:key.keyboard.unknown
          key_key.fullscreen:key.keyboard.f11
          key_key.spectatorOutlines:key.keyboard.unknown
          key_key.swapOffhand:key.keyboard.f
          key_key.saveToolbarActivator:key.keyboard.c
          key_key.loadToolbarActivator:key.keyboard.x
          key_key.advancements:key.keyboard.l
          key_key.hotbar.1:key.keyboard.unknown
          key_key.hotbar.2:key.keyboard.unknown
          key_key.hotbar.3:key.keyboard.unknown
          key_key.hotbar.4:key.keyboard.unknown
          key_key.hotbar.5:key.keyboard.unknown
          key_key.hotbar.6:key.keyboard.unknown
          key_key.hotbar.7:key.keyboard.unknown
          key_key.hotbar.8:key.keyboard.unknown
          key_key.hotbar.9:key.keyboard.unknown
          key_key.dynamic_fps.toggle_forced:key.keyboard.unknown
          key_key.dynamic_fps.toggle_disabled:key.keyboard.unknown
          key_artifacts.key.helium_flamingo.activate:key.keyboard.unknown
          key_artifacts.key.charm_of_shrinking.toggle:key.keyboard.unknown
          key_artifacts.key.charm_of_sinking.toggle:key.keyboard.unknown
          key_artifacts.key.night_vision_goggles.toggle:key.keyboard.unknown
          key_artifacts.key.scarf_of_invisibility.toggle:key.keyboard.unknown
          key_artifacts.key.universal_attractor.toggle:key.keyboard.unknown
          key_key.entityculling.toggle:key.keyboard.unknown
          key_key.jade.config:key.keyboard.keypad.0
          key_key.jade.show_overlay:key.keyboard.keypad.1
          key_key.jade.toggle_liquid:key.keyboard.keypad.2
          key_key.jade.narrate:key.keyboard.keypad.5
          key_key.jade.show_details_alternative:key.keyboard.unknown
          key_key.logical_zoom.zoom:key.keyboard.left.bracket
          key_key.mca.skin_library:key.keyboard.f1
          key_key.modmenu.open_menu:key.keyboard.unknown
          key_supplementaries.keybind.quiver:key.keyboard.v
          key_key.presencefootsteps.settings:key.keyboard.f10
          key_key.presencefootsteps.toggle:key.keyboard.unknown
          key_key.puffish_skills.open:key.keyboard.semicolon
          key_key.simplytooltips.cycle_tab:key.keyboard.g
          key_key.simplytooltips.capture_gif:key.keyboard.h
          key_key.smallships.ship_sail:key.keyboard.f3
          key_key.smallships.cannon_barrel_enter:key.keyboard.f4
          key_keybindings.spell_engine.bypass_spell_hotbar:key.keyboard.left.alt
          key_keybindings.spell_engine.spell_hotbar_1:key.keyboard.1
          key_keybindings.spell_engine.spell_hotbar_2:key.keyboard.2
          key_keybindings.spell_engine.spell_hotbar_3:key.keyboard.3
          key_keybindings.spell_engine.spell_hotbar_4:key.keyboard.4
          key_keybindings.spell_engine.spell_hotbar_5:key.keyboard.5
          key_keybindings.spell_engine.spell_hotbar_6:key.keyboard.6
          key_keybindings.spell_engine.spell_hotbar_7:key.keyboard.7
          key_keybindings.spell_engine.spell_hotbar_8:key.keyboard.8
          key_keybindings.spell_engine.spell_hotbar_9:key.keyboard.9
          key_key.toms_storage.open_terminal:key.keyboard.equal
          key_key.travelersbackpack.inventory:key.keyboard.period
          key_key.travelersbackpack.sort:key.keyboard.unknown
          key_key.travelersbackpack.ability:key.keyboard.comma
          key_key.travelersbackpack.cycle_tool:key.keyboard.z
          key_key.travelersbackpack.toggle_upgrade_0:key.keyboard.unknown
          key_key.travelersbackpack.toggle_upgrade_1:key.keyboard.unknown
          key_key.travelersbackpack.toggle_upgrade_2:key.keyboard.unknown
          key_key.travelersbackpack.toggle_upgrade_3:key.keyboard.unknown
          key_gui.xaero_minimap_settings:key.keyboard.y
          key_gui.xaero_minimap_server_profiles:key.keyboard.unknown
          key_gui.xaero_zoom_in:key.keyboard.unknown
          key_gui.xaero_zoom_out:key.keyboard.unknown
          key_gui.xaero_new_waypoint:key.keyboard.b
          key_gui.xaero_waypoints_key:key.keyboard.u
          key_gui.xaero_enlarge_map:key.keyboard.n
          key_gui.xaero_toggle_map:key.keyboard.unknown
          key_gui.xaero_toggle_waypoints:key.keyboard.unknown
          key_gui.xaero_toggle_map_waypoints:key.keyboard.unknown
          key_gui.xaero_toggle_slime:key.keyboard.unknown
          key_gui.xaero_toggle_grid:key.keyboard.unknown
          key_gui.xaero_instant_waypoint:key.keyboard.keypad.add
          key_gui.xaero_switch_waypoint_set:key.keyboard.unknown
          key_gui.xaero_display_all_sets:key.keyboard.unknown
          key_gui.xaero_toggle_light_overlay:key.keyboard.unknown
          key_gui.xaero_toggle_entity_radar:key.keyboard.unknown
          key_gui.xaero_reverse_entity_radar:key.keyboard.unknown
          key_gui.xaero_toggle_manual_cave_mode:key.keyboard.unknown
          key_gui.xaero_alternative_list_players:key.keyboard.unknown
          key_gui.xaero_toggle_tracked_players_on_map:key.keyboard.unknown
          key_gui.xaero_toggle_tracked_players_in_world:key.keyboard.unknown
          key_gui.xaero_toggle_pac_chunk_claims:key.keyboard.unknown
          key_gui.xaero_open_map:key.keyboard.m
          key_gui.xaero_open_settings:key.keyboard.right.bracket
          key_gui.xaero_world_map_server_settings:key.keyboard.unknown
          key_gui.xaero_map_zoom_in:key.keyboard.unknown
          key_gui.xaero_map_zoom_out:key.keyboard.unknown
          key_gui.xaero_quick_confirm:key.keyboard.right.shift
          key_gui.xaero_toggle_dimension:key.keyboard.unknown
          key_iris.keybind.reload:key.keyboard.home
          key_iris.keybind.toggleShaders:key.keyboard.delete
          key_iris.keybind.shaderPackSelection:key.keyboard.o
          key_iris.keybind.wireframe:key.keyboard.unknown
          key_lambdynlights.key.toggle_fps_dynamic_lighting:key.keyboard.unknown
          soundCategory_master:0.19624496985562814
          soundCategory_music:1.0
          soundCategory_record:1.0
          soundCategory_weather:1.0
          soundCategory_block:1.0
          soundCategory_hostile:1.0
          soundCategory_neutral:1.0
          soundCategory_player:1.0
          soundCategory_ambient:1.0
          soundCategory_voice:1.0
          modelPart_cape:true
          modelPart_jacket:true
          modelPart_left_sleeve:true
          modelPart_right_sleeve:true
          modelPart_left_pants_leg:true
          modelPart_right_pants_leg:true
          modelPart_hat:true
        ''; }
    ] ++ (let shaders = hdShaders
             ++ lib.optionals (i.ip == stagingAddress) hdTrialShaders; in
      map (sh: {
        path = "${dir}/minecraft/shaderpacks/${sh.name}";
        src = pkgs.fetchurl { inherit (sh) url sha512; };
      }) shaders
      ++ lib.concatMap (sh: lib.optional (sh ? settings) {
        path = "${dir}/minecraft/shaderpacks/${sh.name}.txt";
        src = pkgs.writeText "${sh.name}.txt"
          (lib.concatStringsSep "\n"
            (lib.mapAttrsToList (k: v: "${k}=${v}") sh.settings) + "\n");
      }) shaders)
    ++ [{
      path = "${dir}/minecraft/resourcepacks/${hdResourcePack.name}";
      src = pkgs.fetchurl { inherit (hdResourcePack) url sha512; };
    }]
    ++ [{
      path = "${dir}/minecraft/resourcepacks/${hdFixPack.name}";
      src = hdFixPack.src;
      sweep = "${dir}/minecraft/resourcepacks";
      family = "AkuCraft-Patrix-fixes";
      keep = hdFixPack.name;
    }]
    ++ map (m: {
      path = "${dir}/minecraft/mods/${m.name}"
        + lib.optionalString (m.disabled or false) ".disabled";
      src = pkgs.fetchurl { inherit (m) url sha512; };
      # Bumping a version leaves the old jar behind, and two Sodiums will not
      # load. Sweep anything matching the same family but a different name.
      sweep = "${dir}/minecraft/mods";
      keep = m.name;
      # A mod seeded disabled is the player's to switch on: enabling it in the
      # launcher renames the file, and neither the sweep nor the seeder may
      # undo that - otherwise every sync-user.sh would silently turn it back
      # off, or leave both copies and stop Fabric from starting.
      keepAlso = lib.optionalString (m.disabled or false) "${m.name}.disabled";
      skipIf = lib.optionalString (m.disabled or false)
        "${dir}/minecraft/mods/${m.name}";
      family = builtins.head (lib.splitString "-" m.name);
    }) hdMods
    ++ map (pack: {
      path = "${dir}/minecraft/resourcepacks/${pack.name}";
      # A pack whose own filename has spaces or brackets cannot name a store
      # path, so those carry an explicit storeName.
      src = pkgs.fetchurl ({ inherit (pack) url sha512; }
        // lib.optionalAttrs (pack ? storeName) { name = pack.storeName; });
    }) (hdPacks ++ lib.optionals (i.ip == stagingAddress) hdTrialPacks);

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
        ${lib.optionalString ((f.keepAlso or "") != "") ''
          [ "$(basename "$old")" = "${f.keepAlso}" ] && continue''}
        rm -f "$old" && echo "removed superseded $(basename "$old")"
      done
    ''}
    if [ ! -f "$HOME/${f.path}" ] ${lib.optionalString ((f.skipIf or "") != "")
        ''&& [ ! -f "$HOME/${f.skipIf}" ]''} || [ -L "$HOME/${f.path}" ]; then
      rm -f "$HOME/${f.path}"
      mkdir -p "$(dirname "$HOME/${f.path}")"
      install -m 644 ${f.src} "$HOME/${f.path}"
      echo "seeded ${f.path}"
    fi
  '') (lib.concatMap hdSeed hdInstances ++ lib.concatMap plainSeed plainInstances);
in
{

  home.activation.akucraftHdInstances =
    lib.hm.dag.entryAfter [ "writeBoundary" ] hdSeedScript;

  # --- Route the launcher through gamemoderun -----------------------------
  # WHY this exists at all: the local LLM and Minecraft cannot share this card
  # any more. Measured 2026-09-01 on the RX 9070 XT (16304 MiB):
  #   desktop (Sway + browser + editor) .... 2.9 GiB
  #   one AkuCraft HD client ............... 3.9 GiB   (was 2.0 GiB in Aug, before ULTRA shaders)
  #   gpt-oss:20b resident ................ 11.9 GiB
  # That totals 18.7 GiB. Worse, ROCm reports the card as nearly empty no matter
  # what else is on it, so Ollama loads anyway and amdgpu answers with
  # "Not enough memory for command submission!" — which on 2026-09-01 killed a
  # running Minecraft client. The lock is what prevents that.
  #
  # gamemoderun rather than PreLaunchCommand=llama-lock on purpose. A
  # PostExitCommand does not run if the game or the launcher dies hard, and a
  # lock left behind is silent and expensive: the villagers would fall back to
  # paid DeepSeek indefinitely with nothing to show it. gamemoded drops the
  # client when its process disappears, crash included, so the unlock always
  # happens.
  #
  # /run/current-system/sw/bin is deliberate: it follows the active generation,
  # where a /nix/store path baked into the config would break on GC.
  #
  # Only the GLOBAL key is touched. Every AkuCraft instance ships
  # OverrideCommands=false, so all of them inherit it; an instance that opts out
  # keeps its own setting, which is the escape hatch if one game needs it.
  home.activation.freesmGamemodeWrapper =
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        cfg = "$HOME/.local/share/FreesmLauncher/freesmlauncher.cfg";
        want = if (systemSettings.freesmLauncherGamemodeWrapper or false)
               then "/run/current-system/sw/bin/gamemoderun" else "";
      in ''
        if [ -f "${cfg}" ]; then
          current=$(${pkgs.gnugrep}/bin/grep -E '^WrapperCommand=' "${cfg}" | ${pkgs.coreutils}/bin/cut -d= -f2- || true)
          if [ "$current" != "${want}" ]; then
            if ${pkgs.gnugrep}/bin/grep -qE '^WrapperCommand=' "${cfg}"; then
              ${pkgs.gnused}/bin/sed -i 's|^WrapperCommand=.*|WrapperCommand=${want}|' "${cfg}"
            else
              echo 'WrapperCommand=${want}' >> "${cfg}"
            fi
            echo "FreesmLauncher WrapperCommand -> '${want}'"
          fi
        else
          # First run has not happened yet; the launcher writes this file itself
          # and the next activation will set the key.
          echo "FreesmLauncher config not present yet — WrapperCommand not set"
        fi
      '');
}
