# Keeps the library's Nether portal from dumping monsters into Akunito's claim.
#
# WHY THIS IS NEEDED EVEN THOUGH THE NETHER MOUTH IS SEALED: that portal is
# plain vanilla obsidian (NOT one of our gateways), and a live portal standing
# in a "natural" dimension SPAWNS ZOMBIFIED PIGLINS BY ITSELF - nothing has to
# walk through it. The per-tick chance scales with difficulty and this server
# runs Hard, the maximum, so it works out to roughly one piglin every couple of
# hours of loaded time. Walling the Nether side (2026-08-27) stopped everything
# that WALKED through and could never have stopped these.
#
# BLOCKLIST, NEVER AN ALLOW-LIST. "kill anything that is not a player or a pet"
# would also delete dropped items, item frames, paintings, boats, armour stands
# and the library's villagers. minecraft:zombie_villager is deliberately absent
# from the tag: a zombified villager is something you cure, not something you
# shred.
#
# Positioned selector on purpose - an un-positioned @e searches EVERY dimension
# on this server.
execute in minecraft:overworld positioned -451.5 -43.0 -1712.5 run kill @e[type=#akuportal:portal_intruders,distance=..8]
