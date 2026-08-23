# Closed-loop clock: every 3 ticks, SET the absolute day time (day*24000 +
# daytime - "time set" with only the daytime would reset the day counter and
# freeze the moon) to a virtual clock advanced by 1. Net: x3 slower on any
# server - open-loop "subtract 2" broke on survival, where Multiworld eats one
# tick of advancement after every time set.
# A jump beyond the 0..10 window means the world moved without us (sleeping
# through the night, an admin /time set, a restart with stale scoreboards):
# adopt the new time instead of yanking the world back.
scoreboard players set #t slowtime_t 0
execute store result score #day slowtime_t run time query day
execute store result score #abs slowtime_t run time query daytime
scoreboard players operation #day slowtime_t *= #k24000 slowtime_t
scoreboard players operation #abs slowtime_t += #day slowtime_t
scoreboard players operation #diff slowtime_t = #abs slowtime_t
scoreboard players operation #diff slowtime_t -= #last slowtime_t
# Count and size every adoption, so "who moved the clock" is answerable
# after the fact. A vanilla night-skip shows up here as one jump of
# roughly (24000 - the daytime it was); two jumps for one night means
# something fired twice. Startup and any admin /time set also show up.
execute unless score #diff slowtime_t matches 0..10 run scoreboard players add #dbg_jump slowtime_t 1
execute unless score #diff slowtime_t matches 0..10 run scoreboard players operation #dbg_jumpsz slowtime_t = #diff slowtime_t
execute unless score #diff slowtime_t matches 0..10 run scoreboard players operation #last slowtime_t = #abs slowtime_t
execute if score #diff slowtime_t matches 0..10 run scoreboard players add #last slowtime_t 1
execute store result storage slowtime:tmp t int 1 run scoreboard players get #last slowtime_t
function slowtime:apply with storage slowtime:tmp
