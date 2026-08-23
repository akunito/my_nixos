# Night-skip for the Multiworld dimensions (the frontier).
#
# Vanilla's night-skip runs per level. In a Multiworld world it wakes the
# players but its setDayTime lands in derived level data and moves nothing, so
# the night never ends. We own the clock, so we make the jump ourselves.
#
# WHY THIS RUNS EVERY TICK instead of from rewind every 3rd tick
# (fixed 2026-08-23): the window is exactly ONE tick wide.
# ServerPlayer.sleepCounter reaches 100 during level tick N; ServerLevel's
# sleep check sees it on tick N+1 and calls wakeUpAllPlayers() immediately,
# which zeroes it. Function tags run BEFORE levels in tickChildren, so tick
# N+1 is our only chance to observe SleepTimer:100 - and sampling one tick in
# three missed it two times out of three. That is why sleeping in the frontier
# worked occasionally and then appeared to stop.
#
# WHY THE OVERWORLD IS EXCLUDED: where vanilla's skip does work it fires on
# that same tick N+1, reading the time we just wrote and adding another 24000
# on top - two days for one night. So any Overworld sleeper is left to vanilla,
# and the frontier follows for free, because the closed loop in rewind reads
# the Overworld clock and time set writes to every level at once. Our skip is
# only for the case vanilla cannot handle: nobody in the Overworld at all.
scoreboard players operation #tod slowtime_t = #last slowtime_t
scoreboard players operation #tod slowtime_t %= #k24000 slowtime_t
execute store result score #slp slowtime_t run execute if entity @a[nbt={SleepTimer:100s}]
execute store result score #plr slowtime_t run execute if entity @a[gamemode=!spectator]
# A dimension-scoped count needs a POSITIONAL selector: on this server a bare
# @a/@e lookup reaches into every dimension at once (measured 2026-08-22).
execute store result score #ow slowtime_t run execute in minecraft:overworld positioned 0 0 0 if entity @a[gamemode=!spectator,distance=..30000000]
# Diagnostics, so the next regression takes five minutes and not an hour:
#   scoreboard players get #dbg_deep slowtime_t  -> ticks seen with a deep sleeper
#   scoreboard players get #dbg_skip slowtime_t  -> nights this pack skipped
execute if score #slp slowtime_t matches 1.. run scoreboard players add #dbg_deep slowtime_t 1
execute if score #tod slowtime_t matches 12000.. if score #ow slowtime_t matches 0 if score #plr slowtime_t matches 1.. if score #slp slowtime_t >= #plr slowtime_t run function slowtime:skip_night
