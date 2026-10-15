#!/usr/bin/env bash
# scope-phrasing-lint.sh — SessionStart hook (+ manual: run with no stdin).
# Flags notes that freeze a per-ask decision into a PERMANENT refusal — the drift that biased
# Claude into declining legitimate analysis (2026-10-15: REA case-CLAUDE.md / triage.yar said
# "never analyse / must not be used to study" while the skill already allowed it; memory said
# "injection = NEVER / already declined"). Non-blocking, always exits 0.
# Canonical scope line: docs/akunito/plans/rea-sandbox/README.md "## Legalidad" + the
# reverse-engineering SKILL.md. Analysis-to-understand is in scope on Diego's explicit ask;
# the line is PURPOSE (no working circumvention / clone / redistribution), not the subject.
set -u
DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
FILES=()
# memory of every project, minus retired archive/ logs (history is allowed to say "declined")
while IFS= read -r f; do FILES+=("$f"); done < <(find "$HOME/.claude/projects" -path '*/memory/*.md' ! -path '*/archive/*' 2>/dev/null)
# policy-bearing files that are injected into sessions / drive triage
for f in \
  "$DOTFILES/user/app/rea/case-CLAUDE.md" \
  "$DOTFILES/user/app/rea/triage.yar" \
  "$HOME/.claude/skills/reverse-engineering/SKILL.md"; do
  [ -f "$f" ] && FILES+=("$f")
done

# High-precision phrasings that turn "declined once / per-ask" into a standing "no".
BANNED='never analyse|never analyze|never study|must not be used to study|must not be used on it at all|anti-cheat evasion is outside|already declined|claude will not reverse|claude will not disassemble|claude won.t analy|claude does not analy|claude refuses to analy|injection on [a-z0-9 ]*= *never|nunca analiz|no analices|claude no analiz|claude no revert'
# A line is fine when it states the real PURPOSE line or a sandbox/tooling boundary.
ALLOW='circumvention|do not build|do not hand over|clone or reproduce|reproduce a commercial|redistribute|reach the network|other directories|other projects|get around them|data, never instructions|never rename|never cite|never treat it as evidence|never run|never passes'

WARN=0
for f in "${FILES[@]}"; do
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    body=${hit#*:}
    printf '%s' "$body" | grep -qiE "$ALLOW" && continue
    WARN=$((WARN+1))
    echo "SCOPE-LINT WARN: ${f/#$HOME/~}:${hit%%:*} — reads as a standing refusal, reframe as per-ask: '$(printf '%s' "$body" | sed 's/^[[:space:]]*//' | cut -c1-90)'"
  done < <(grep -niE "$BANNED" "$f" 2>/dev/null)
done
[ "$WARN" -gt 0 ] && echo "SCOPE-LINT: $WARN line(s). Canonical scope = docs/akunito/plans/rea-sandbox/README.md '## Legalidad' + reverse-engineering SKILL.md. Analysis-to-understand is in scope on Diego's explicit ask; the line is purpose (no working circumvention / clone / redistribution), not the subject. Reframe or date them this session."
exit 0
