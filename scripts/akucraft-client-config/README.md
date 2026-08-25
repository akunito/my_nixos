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

IPN's own editor help says "Usually it's necessary to set this to true for
both Container and Screen", so both classes of each block are listed. The
keys are Fabric intermediary names, verified against the jars we ship (NOT
guessed — re-verify on a Minecraft version bump):
- `net.minecraft.class_3802` = GrindstoneScreen (grind-enchantments'
  GrindstoneScreenMixin targets it)
- `net.minecraft.class_3803` = GrindstoneScreenHandler (its refmap)
- `net.minecraft.class_471` = AnvilScreen (IPN's own accesswidener touches
  `class_471 field_2821`)
- `net.minecraft.class_1706` = AnvilScreenHandler (grind-enchantments'
  MoveOperation calls its getNextCost)

Players can do the same by hand, no file needed: IPN's in-game Overlay
Editor has Screen -> Ignore and Container -> Ignore per GUI.

### Field notes (2026-08-25, IPN 2.2.6)

- IPN's in-game Overlay Editor EDITS these hint files in place: flipping
  "Ignore" off DELETED our grindstone entries from the delivered akucraft.json.
  AutoModpack restores the file on the next launcher start (hash mismatch), so
  player experiments self-heal.
- The editor can MOVE buttons (writes player-defined.json) and can turn Ignore
  OFF, but cannot turn Ignore ON. Enabling ignore is file-only.
