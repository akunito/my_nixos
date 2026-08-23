# Two-way link between the upper claim archway and the lower one.
#
#   UPPER  arch plane z=-1730, opening x -449..-447, y 98..100
#   LOWER  arch plane x=-446,  opening z -1711..-1709, y -44..-42
#
# Each exit sits ONE block outside the far trigger box, so stepping out
# never re-triggers the portal you just came through.
#
# Exits face away from the arch, toward the room you arrive in:
#   upper exit looks north (yaw 180) - out into the greenhouse
#   lower exit looks west  (yaw 90)  - out into the library
execute in minecraft:overworld as @a[x=-449,y=98,z=-1730,dx=3,dy=3,dz=1] at @s run function akuportal:go_down
execute in minecraft:overworld as @a[x=-446,y=-44,z=-1711,dx=1,dy=3,dz=3] at @s run function akuportal:go_up

# Frontier gateway (2026-08-21, no quest): coast arch nearest world spawn.
#   OVERWORLD arch plane x=-152 (mossy pyramid, cloned from frontier), opening z 53..55, y 70..72
#   FRONTIER  arch plane x=-1468 (Yosemite mountain edge), opening z -185..-183, y 149..151
# Same one-block-outside exit rule as the claim arches above.
execute in minecraft:overworld as @a[x=-152,y=70,z=53,dx=0,dy=2,dz=2] at @s run function akuportal:go_frontier
execute in multiworld:frontier as @a[x=-1468,y=149,z=-185,dx=0,dy=2,dz=2] at @s run function akuportal:go_home_frontier
