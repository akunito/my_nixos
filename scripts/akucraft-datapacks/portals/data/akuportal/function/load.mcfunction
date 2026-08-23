# SOURCE OF TRUTH: scripts/akucraft-datapacks/ in the dotfiles repo.
# Deploy with scripts/sync-akucraft-datapacks.py --target prod --push.
# Editing the copy inside the world folder works until the next sync,
# and then silently loses your change.
scoreboard objectives add akuportal.fx dummy
