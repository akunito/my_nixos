# Night-skip for the Multiworld dimensions (the frontier).
#
# Vanilla's night-skip runs PER LEVEL: ServerLevel.sleepStatus counts only the
# players in that level. In a Multiworld world it therefore fires the whole
# sequence - the message, the fade, wakeUpAllPlayers() - but its setDayTime
# lands in derived level data and moves nothing, so the night never ends. We
# own the clock, so we make the jump ourselves.
#
# THE CONDITION IS PER-WORLD, and getting that wrong cost a test round on
# 2026-08-23: the first version required every non-spectator player on the
# SERVER to be asleep and refused outright if anyone stood in the Overworld.
# That is stricter than vanilla and blocked the exact case this exists for -
# one player asleep in the frontier while somebody else is awake at home.
# Diego caught it: "komi no cuenta cuando está en otro mundo diferente, solo
# cuentan los jugadores que están en ese mundo". He is right, so now the
# frontier's own players decide the frontier's night.
#
# The trade this accepts: there is ONE clock (time set writes every level at
# once), so skipping the night in the frontier skips it in the Overworld too.
# Somebody mining at home loses their night to a sleeper in the frontier. That
# is a deliberate choice for a four-player server, not an oversight.
#
# WHY IT RUNS EVERY TICK: the window is exactly one tick wide. sleepCounter
# reaches 100 during level tick N; ServerLevel sees it on tick N+1 and calls
# wakeUpAllPlayers() at once. Function tags run before levels in tickChildren,
# so N+1 is our only look - and sampling one tick in three missed it twice out
# of three times.
#
# WHY WE STAND DOWN WHEN THE OVERWORLD IS ALREADY SATISFIED: there vanilla's
# skip really works, and it fires on that same tick N+1 reading the time we
# just wrote - another 24000 on top, two days for one night. So if the
# Overworld's own sleep condition is met, we leave it alone and let the closed
# loop in rewind adopt vanilla's jump. An EMPTY Overworld does not count as
# satisfied: vanilla needs at least one sleeper to fire.
#
# Dimension-scoped counts need a POSITIONAL selector. A bare @a or @e on this
# server reaches into every dimension at once (measured 2026-08-22), so the
# distance= is what makes these read one world instead of all of them.
scoreboard players operation #tod slowtime_t = #last slowtime_t
scoreboard players operation #tod slowtime_t %= #k24000 slowtime_t

execute store result score #frplr slowtime_t run execute in multiworld:frontier positioned 0 0 0 if entity @a[gamemode=!spectator,distance=..30000000]
execute store result score #frslp slowtime_t run execute in multiworld:frontier positioned 0 0 0 if entity @a[nbt={SleepTimer:100s},distance=..30000000]
execute store result score #owplr slowtime_t run execute in minecraft:overworld positioned 0 0 0 if entity @a[gamemode=!spectator,distance=..30000000]
execute store result score #owslp slowtime_t run execute in minecraft:overworld positioned 0 0 0 if entity @a[nbt={SleepTimer:100s},distance=..30000000]

# Is vanilla about to do the job for us in the Overworld?
scoreboard players set #owfires slowtime_t 0
execute if score #owplr slowtime_t matches 1.. if score #owslp slowtime_t >= #owplr slowtime_t run scoreboard players set #owfires slowtime_t 1

# Diagnostics, so the next regression takes five minutes and not an hour:
#   #dbg_deep  ticks seen with a deep sleeper in the frontier
#   #dbg_skip  nights this pack skipped
#   #dbg_jump  times the world clock moved without us, #dbg_jumpsz the last size
execute if score #frslp slowtime_t matches 1.. run scoreboard players add #dbg_deep slowtime_t 1

execute if score #tod slowtime_t matches 12000.. if score #owfires slowtime_t matches 0 if score #frplr slowtime_t matches 1.. if score #frslp slowtime_t >= #frplr slowtime_t run function slowtime:skip_night
