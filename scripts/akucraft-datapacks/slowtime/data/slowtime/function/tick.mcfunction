# Every 3rd tick rewind the clock by 2, so the day/night cycle nets +1 per 3
# ticks = 1/3 speed. time add rejects negative values, hence the set-via-macro
# dance in rewind.
scoreboard players add #t slowtime_t 1
execute if score #t slowtime_t matches 3.. run function slowtime:rewind

# Sleep is checked EVERY tick, deliberately. See sleep.mcfunction.
function slowtime:sleep
