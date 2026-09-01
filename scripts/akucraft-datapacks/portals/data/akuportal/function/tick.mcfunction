# Portal curtains. Switch with: scoreboard players set FX akuportal.fx <n>
#   1 classic purple · 2 soul fire · 3 arcane · 4 custom dust · 5 dark blue
execute if score FX akuportal.fx matches 1 run function akuportal:fx1
execute if score FX akuportal.fx matches 2 run function akuportal:fx2
execute if score FX akuportal.fx matches 3 run function akuportal:fx3
execute if score FX akuportal.fx matches 4 run function akuportal:fx4
execute if score FX akuportal.fx matches 5 run function akuportal:fx5
function akuportal:link

# Frontier gateway curtains - always on, independent of the FX selector.
execute in minecraft:overworld run particle minecraft:reverse_portal -151.5 71.5 54.5 0.05 1.2 1.2 0.01 8 force
execute in multiworld:frontier run particle minecraft:reverse_portal -1467.5 150.5 -183.5 0.05 1.2 1.2 0.01 8 force

# Library Nether portal - see nether_guard for why a sealed portal still leaks.
function akuportal:nether_guard

# Friendly things trapped in the sealed Nether chamber - send them home.
function akuportal:chamber_rescue
