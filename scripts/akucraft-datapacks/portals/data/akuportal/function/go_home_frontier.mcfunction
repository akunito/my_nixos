# Frontier arch -> Overworld coast arch. Mirror of go_frontier.
playsound minecraft:entity.enderman.teleport master @a ~ ~ ~ 0.8 0.7
function akuportal:pets_mark
execute as @e[tag=akuportal.follow] in minecraft:overworld run tp @s -150.5 70 54.5
execute in minecraft:overworld run tag @e[tag=akuportal.follow] remove akuportal.follow
execute in minecraft:overworld run tp @s -150.5 70 54.5 -90 0
execute in minecraft:overworld run playsound minecraft:entity.enderman.teleport master @a -150.5 70 54.5 0.8 1.3
