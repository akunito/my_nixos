# SOURCE OF TRUTH: scripts/akucraft-datapacks/ in the dotfiles repo.
# Deploy with scripts/sync-akucraft-datapacks.py --target prod --push.
# Editing the copy inside the world folder works until the next sync,
# and then silently loses your change.
scoreboard objectives add slowtime_t dummy
scoreboard players set #k24000 slowtime_t 24000
scoreboard players add #last slowtime_t 0
scoreboard players add #dbg_deep slowtime_t 0
scoreboard players add #dbg_skip slowtime_t 0
