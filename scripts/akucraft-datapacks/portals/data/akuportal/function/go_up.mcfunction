# Lower library arch -> upper greenhouse arch. Same dimension, so no `in`.
playsound minecraft:entity.enderman.teleport master @a ~ ~ ~ 0.8 0.7
function akuportal:pets_mark
tp @e[tag=akuportal.follow] -447.5 98 -1731.5
tag @e[tag=akuportal.follow] remove akuportal.follow
tp @s -447.5 98 -1731.5 180 0
playsound minecraft:entity.enderman.teleport master @a ~ ~ ~ 0.8 1.3
