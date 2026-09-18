# Projects — one window, two projects

This directory is a **workspace, not a project**. Two real projects live under it, each with its
own repository, its own rules and its own website:

| Directory | Plane project | What it is |
|---|---|---|
| `babydocs/` | IRIN | Research, decisions and records about Irenka |
| `homedocs/` | HOME | The flat, services, paperwork, maintenance |

If one of those directories is not there, that project has not been set up yet — say so instead of
improvising a place to put things.

## Rules

1. **One project per conversation.** Before touching any file, work out which project the request
   belongs to. If it is not obvious, **ask** — never guess.
2. **Say which project you are in** in the first line of your first answer — "Irenka (babydocs)" or
   "Home (homedocs)". The person in front of you needs to see it, every time.
3. **Read that project's `CLAUDE.md` before acting.** Its rules win over anything written here.
4. **Never write outside the chosen project.** Not a file in the other project, not a file in this
   directory.
5. **If the conversation drifts to the other project, stop and say so**: "that one belongs to Home —
   shall we switch?" Park or finish the current topic first. Never mix two projects in one research,
   one commit, or one ticket.
6. **Questions that belong to neither project** — a recipe, a translation, how something works — are
   answered in the chat. Touch no repository and commit nothing.
7. **Sync only the active project**: `tools/sync.sh` inside it, never both.
8. **Name every auto-memory after its project** (`babydocs_…`, `homedocs_…`). Both projects share
   one memory directory here, and a memory without an owner is a memory that gets misapplied.

## Language

Answer in the language you are written to — Polish with Aga, Spanish with Diego. Everything written
to disk stays in English, in both projects.
