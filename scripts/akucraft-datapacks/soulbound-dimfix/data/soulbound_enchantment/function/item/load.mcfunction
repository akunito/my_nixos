# OVERRIDE of ly-soulbound-enchantment's item/load (world datapacks outrank
# mod data). Upstream parks every captured item at 0,1000,0 IN THE OVERWORLD;
# its return tick then does "on origin", which only resolves the owner inside
# the ITEM's own dimension - so anyone who dies in a Multiworld dimension
# (frontier) never gets their items back until they happen to visit the
# overworld. Parking in the CURRENT dimension instead keeps item and owner
# together for the common die-and-respawn-in-the-same-world case.
tag @s add soulbound_enchantment.item

data modify entity @s Motion set value [0, 0, 0]
data modify entity @s NoGravity set value 1b
data modify entity @s Invulnerable set value 1b
data modify entity @s Age set value -32768
data modify entity @s PickupDelay set value 0
data modify entity @s Thrower set from entity @p[scores={soulbound_enchantment.player.death=1..}] UUID
data modify entity @s Owner set from entity @p[scores={soulbound_enchantment.player.death=1..}] UUID

item modify entity @s container.0 soulbound_enchantment:damage

forceload add 0 0 0 0

tp @s 0 1000 0
