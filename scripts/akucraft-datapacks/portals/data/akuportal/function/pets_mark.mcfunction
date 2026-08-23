# Tag the travelling player's own companions so a gateway can carry them along.
#
# Runs AS the traveller, AT the traveller, in their dimension.
#
# WHY THIS EXISTS: our gateways are a datapack `tp @s`, and `tp` moves exactly
# one entity. A vanilla nether portal drags nearby pets through; ours never
# did, which is why komi's wolf stayed in the Overworld on 2026-08-22.
#
# HOW THE OWNERSHIP TEST WORKS: `on owner` rebinds @s to the pet's owner but
# leaves the execution POSITION standing on the pet, so the tag can be handed
# straight back to whatever is at that exact spot. tag=! plus limit=1 makes two
# pets stacked in the same block resolve to two different entities across the
# two iterations instead of tagging one of them twice.
#
# Sitting pets are left behind on purpose - "sit" means stay, in every world.
tag @s add akuportal.traveller
execute as @e[type=#akuportal:pets,distance=..16,nbt=!{Sitting:1b}] at @s on owner if entity @s[tag=akuportal.traveller] run tag @e[type=#akuportal:pets,distance=..0.5,tag=!akuportal.follow,limit=1] add akuportal.follow
tag @s remove akuportal.traveller
