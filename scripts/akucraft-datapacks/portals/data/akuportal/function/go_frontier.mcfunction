# Overworld coast arch -> frontier arrival.
# Pets first, then the player, so nobody arrives to an empty clearing.
playsound minecraft:entity.enderman.teleport master @a ~ ~ ~ 0.8 0.7
function akuportal:pets_mark
execute as @e[tag=akuportal.follow] in multiworld:frontier run tp @s -1466.5 150 -183.5
execute in multiworld:frontier run tag @e[tag=akuportal.follow] remove akuportal.follow
execute in multiworld:frontier run tp @s -1466.5 150 -183.5 -90 0
execute in multiworld:frontier run playsound minecraft:entity.enderman.teleport master @a -1466.5 150 -183.5 0.8 1.3
