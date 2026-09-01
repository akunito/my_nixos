# Sends home anything friendly that ends up in the sealed Nether chamber.
#
# WHY: the Nether mouth of the library portal was walled into a 2-block-high
# box on 2026-08-27 to keep monsters out of the claim. That box is a one-way
# trap for anything that follows a player through - komi's wolf (2026-08-27), a
# cat, and an iron golem that SUFFOCATED in there on 2026-08-28 because it is
# 2.7 blocks tall and the ceiling is deliberately 2. The height is what keeps
# endermen (2.9) from teleporting in, so the ceiling stays and this runs instead.
#
# Radius 12, not just the chamber box: two of komi's wolves were found stranded
# 5 and 10 blocks OUTSIDE the walls, left over from trips made before the seal.
# minecraft:strider is the only friendly that spawns in the Nether naturally and
# it is deliberately NOT in the tag, so nothing native gets yanked.
#
# minecraft:item IS in the tag on purpose - losing a death drop in a sealed box
# nobody can reach is worse than a stack arriving in the library unannounced.
#
# If the iron door is ever restored and you WANT pets in the Nether again, this
# is the line that will keep dragging them home. Remove it then.
execute in minecraft:the_nether positioned -58.5 32.5 -230.5 as @e[distance=..12,type=#akuportal:portal_rescue] in minecraft:overworld run tp @s -453.5 -45.0 -1717.5
