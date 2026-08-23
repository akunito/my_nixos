# Round the virtual clock up to the next multiple of 24000 (= morning) and
# apply it. The closed loop adopts the jump on its next cycle, and vanilla
# wakes the sleepers on the same tick because its own check still fires - it
# just could not move the clock.
#
# THE "with storage" IS LOAD-BEARING (fixed 2026-08-23). apply.mcfunction is a
# macro ($time set $(t)); calling a macro with no arguments aborts it with
# "Failed to instantiate function slowtime:apply: Missing arguments", which is
# not logged anywhere a player or an admin would look. This function therefore
# bumped its counter, moved its own #last, and never touched the world clock -
# 366 times in one sleep test on 2026-08-23. rewind.mcfunction always passed
# the storage; this one never did.
scoreboard players operation #last slowtime_t /= #k24000 slowtime_t
scoreboard players add #last slowtime_t 1
scoreboard players operation #last slowtime_t *= #k24000 slowtime_t
scoreboard players add #dbg_skip slowtime_t 1
execute store result storage slowtime:tmp t int 1 run scoreboard players get #last slowtime_t
function slowtime:apply with storage slowtime:tmp
