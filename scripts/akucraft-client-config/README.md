# Client config shipped through AutoModpack

Files here are NOT read by anything on this machine. They are copied to each
server's `/data/config/...` and listed in AutoModpack's `syncedFiles`, which
delivers them into every player's instance config — the same mechanism that
ships the chatplus tab preset. `sync-akucraft-automodpack.py` preserves any
non-`/mods/` entry in `syncedFiles`, so the entry survives re-syncs.

## inventoryprofilesnext-integrationHints-akucraft.json

Deployed as `/data/config/inventoryprofilesnext/integrationHints/akucraft.json`.

Inventory Profiles Next draws its sort buttons over Grind Enchantments'
"Enchantment cost" text in the grindstone screen (and crowds the anvil).
IPN merges every `config/inventoryprofilesnext/integrationHints/*.json` over
its built-in hints; `"ignore": true` disables IPN entirely on that screen.

The keys are Fabric intermediary names, verified against the jars we ship
(NOT guessed — re-verify on a Minecraft version bump):
- `net.minecraft.class_3802` = GrindstoneScreen (grind-enchantments'
  GrindstoneScreenMixin targets it; the handler is class_3803)
- `net.minecraft.class_471` = AnvilScreen (IPN's own accesswidener touches
  `class_471 field_2821`)
