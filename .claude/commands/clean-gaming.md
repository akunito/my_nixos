# Clean Gaming Processes

Kill stale gamescope, Wine, and Proton processes left over from previous Skyrim/LoreRim sessions. These processes frequently fail to clean up when Steam games are closed.

## Purpose

Use this skill to:
- Kill orphaned gamescopereaper processes from previous game sessions
- Kill stale winedevice.exe / wineserver / Wine processes
- Clean up without affecting any currently running game session
- Free system resources consumed by zombie gaming processes

---

## Steps

1. **Identify stale processes**: List all gamescope/Wine/Proton processes, distinguishing active from stale
2. **Identify the active session** (if any): The most recently started gamescope process is likely the current session
3. **Ask user for confirmation** before killing, showing which PIDs will be killed and which will be preserved
4. **Kill stale processes**: Use `kill -9` (these processes typically ignore SIGTERM)
5. **Verify cleanup**: Confirm all stale processes are gone

## Process patterns to match

```bash
# Stale process patterns (grep -iE):
gamescopereaper|gamescope|winedevice|wineserver|wine.*server|proton.*waitfor|explorer\.exe|services\.exe|plugplay\.exe|svchost\.exe

# Exclude:
# - The grep process itself
# - Steam client processes (not game-related)
# - Any gamescope process started in the last 5 minutes (likely active)
```

## Safety rules

- **NEVER kill the most recent gamescope process** without asking — it may be the active game session
- **NEVER kill Steam client** processes (steam, steamwebhelper, etc.)
- Always show the user what will be killed before doing it
- Use `kill -9` since these processes ignore regular SIGTERM
