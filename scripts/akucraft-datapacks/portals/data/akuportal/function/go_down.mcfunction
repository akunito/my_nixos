# Upper greenhouse arch -> lower library arch. Same dimension, so no `in`.
playsound minecraft:entity.enderman.teleport master @a ~ ~ ~ 0.8 0.7
function akuportal:pets_mark
tp @e[tag=akuportal.follow] -446.5 -44 -1709.5
tag @e[tag=akuportal.follow] remove akuportal.follow
tp @s -446.5 -44 -1709.5 90 0
playsound minecraft:entity.enderman.teleport master @a ~ ~ ~ 0.8 1.3
