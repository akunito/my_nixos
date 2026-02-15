# LoreRim Survival Mods Overhaul

Guide for adding deep survival mechanics to LoreRim via Frostfall + Campfire + Hunterborn + Scarcity.

---

## Overview of Changes

| System | LoreRim Default (disabled) | Replacement | Why |
|--------|---------------------------|-------------|-----|
| Cold | Survival Mode Improved - SKSE | **Frostfall** + Campfire | Full hypothermia, exposure, warmth system |
| Camping | Rest By Campfire (BOS, minimal) | **Campfire** (full system) | Tents, fires, skills, crafting |
| Hunting | Simple Hunting Overhaul | **Hunterborn** | Deep skinning, processing, foraging, taxonomy |
| Scarcity | (none) | **Scarcity SE** | Reduce loot abundance across the world |
| Needs | Waterskin (hydration only) | Keep existing | SunHelm/SMI already handles hunger/thirst/fatigue |

**Reference:** Wildlander runs Campfire + Frostfall + Hunterborn + SunHelm with Requiem. Its load order is the proven template.

---

## Mods Disabled in modlist.txt

These mods were disabled (changed from `+` to `-`) — not deleted:

| Mod | modlist.txt Line | Reason |
|-----|------------------|--------|
| Survival Mode Improved - SKSE | 1271 | Replaced by Frostfall |
| Compatibility Patch for Static Skill Leveling and Survival Mode Improved | 312 | Depends on SMI |
| Simple Hunting Overhaul | 1257 | Replaced by Hunterborn |
| Simple Hunting Overhaul - MCM | 238 | Depends on SHO |
| Simple Hunting Overhaul - Eating Animations and Sounds Patch | 789 | Depends on SHO |
| Rest By Campfire - Base Object Swapper | 2271 | Replaced by full Campfire |
| Respawn - Soulslike Edition and Rest By Campfire - BOS Patch | 1234 | Depends on Rest By Campfire |
| CYC - SHO hotfix | 1255 | Depends on SHO |
| Carry Your Carcasses | 1256 | Depends on SHO |

## Plugins Disabled in plugins.txt

These plugins had their `*` prefix removed:

| Plugin | Reason |
|--------|--------|
| SurvivalModeImproved.esp | Replaced by Frostfall |
| TasteOfDeath_Addon_RingCurse_SMI.esp | Depends on SMI |
| Static Skill Leveling SMI Patch.esp | Depends on SMI |
| Rest By Campfire - Base Object Swapper.esp | Replaced by Campfire |
| Respawn Rest By Campfire - BOS Version patch.esp | Depends on Rest By Campfire |
| Rest By Campfire - Embers Patch.esp | Depends on Rest By Campfire |
| Simple Hunting Overhaul.esp | Replaced by Hunterborn |
| Simple Hunting Overhaul - MCM.esp | Depends on SHO |
| CarryYourCarcasses - SHO.esp | Depends on SHO |
| Embers XD - Patch - Survival Mode Improved.esp | Depends on SMI |

## Mods Kept Enabled (Compatible)

- CC's Camping Expansion (works alongside Campfire)
- Immersive Hunting Animations (animations only, no mechanic conflict)
- Waterskin - Stay Hydrated (complements Frostfall)
- Survival Control Panel (may still work for some settings)
- Survival Spells / Requiem - Survival Spells (Requiem integration)
- All cooking/food mods (Dead By Dining, Alchemy Requires Bottles, etc.)

---

## Mods to Download and Install

### Download Script

A download script is available at `/mnt/2nd_NVME/Games/Skyrim/download-survival-mods.py`:

```bash
export NEXUS_API_KEY="your-premium-api-key"
python3 /mnt/2nd_NVME/Games/Skyrim/download-survival-mods.py
```

### Core Mods

| # | Mod | Nexus ID | Notes |
|---|-----|----------|-------|
| 1 | Campfire - Complete Camping System | 855 | ESM master — loads very early |
| 2 | Frostfall - Hypothermia Camping Survival | 671 | Requires Campfire |
| 3 | Campfire and Frostfall - Unofficial SSE Update | 17925 | Bug fixes for SE |
| 4 | Frostfall - Seasons | Search Nexus | Seasonal temperature variation |
| 5 | Hunterborn | 7900 | Full hunting overhaul |
| 6 | Hunterborn - Campfire Patch | Bundled with Hunterborn | Campfire integration |
| 7 | Hunterborn SE MCM | Bundled or search | Settings menu |
| 8 | Scarcity SE - Less Loot Mod | 8175 | Leveled list loot reduction |

### Requiem Compatibility Patches

| # | Patch | Source |
|---|-------|--------|
| 9 | Requiem - Campfire/Frostfall/Hunterborn Patch | Search Nexus |
| 10 | Hunterborn - Requiem Patch | May be in all-in-one |
| 11 | Scarcity - Requiem Patch | May need custom xEdit/Synthesis |

### Install Order in MO2

Install in this order (MO2 left pane priority, bottom = highest):

1. **Campfire** — Near position ~1265 (where camping mods are)
2. **Frostfall** — Right after Campfire
3. **Campfire and Frostfall - Unofficial SSE Update** — After Frostfall
4. **Frostfall - Seasons** — After SSE update
5. **Hunterborn** — Near position ~1257 (where hunting mods were)
6. **Hunterborn - Campfire Patch** — After Hunterborn
7. **Hunterborn SE MCM** — After Campfire patch
8. **Scarcity SE** — Near end of gameplay mods section
9. **Requiem patches** — AFTER all the above, high priority (near end)

### Plugin Load Order

Based on Wildlander's proven order:

```
# Early masters (near top, after Skyrim.esm + DLCs)
*Campfire.esm

# Mid load order (~position 500-550)
*Hunterborn.esp
*Hunterborn - Campfire Patch.esp
*Hunterborn - Leather Tanning.esp

# After Hunterborn
*Frostfall.esp
*Frostfall_Seasonal_Temps_patch.esp

# After Frostfall
*Scarcity - Less Loot Mod.esp

# Requiem patches (after Requiem AND the survival mods)
*Requiem - Frostfall Campfire Hunterborn Patch.esp
```

Use **LOOT** to validate and auto-sort, then verify Requiem patches load after both Requiem and survival mods.

---

## Timescale Change

`skyrim.ini` → `[General]`:
```ini
fDefaultWorldTimescale=12
```

Default is 20 (72 min/day). Changed to 12 (~2 real hours/day). This synergizes with survival — more time exposed to cold, more hunger/thirst drain per journey.

### Needs Scaling Considerations

The timescale change from 20 to 12 means game days are ~67% longer in real time. This affects survival needs differently depending on how each mod tracks time:

**Game-time based** (scale automatically): Frostfall exposure is tied to game-time weather/temperature — works correctly at any timescale. Scarcity is loot-based, unaffected.

**Real-time based** (may need MCM adjustment): Some SunHelm/survival needs implementations use real-time intervals. If hunger/thirst/fatigue drain feels too fast after the timescale change, adjust in MCM:
- **Frostfall MCM**: Exposure rate can be reduced if hypothermia feels too punishing
- **SunHelm MCM** (if present): Reduce hunger/thirst/fatigue rates by ~40% to compensate
- **Survival Control Panel**: May have global rate multipliers

Test in-game: if you're starving after a short walk between towns, the needs system is real-time based and needs adjustment.

---

## Post-Install Verification

### Re-run Synthesis Patcher

1. Launch MO2 → Select "Synthesis" from tools dropdown
2. Run existing LoreRim patchers (they detect new plugins)
3. Critical patchers:
   - **Requiem Auto NPC Patcher** — re-balances new NPCs/creatures
   - **Stat Scaler** — ensures new items scale properly
   - **World patcher** — resolves landscape conflicts

### xEdit Conflict Check

1. Load all plugins in SSEEdit
2. Right-click → "Apply Filter for Conflicts"
3. Check record types:
   - **Leveled Items (LVLI)** — Scarcity vs Requiem
   - **Perks (PERK)** — Hunterborn/Frostfall vs Requiem perks
   - **Spells (SPEL)** — Frostfall spells vs Requiem spell balance
   - **Ingredients (INGR)** — Hunterborn new ingredients
4. Create manual patch ESP if critical conflicts found

### In-Game Verification Checklist

- [ ] MO2 shows no missing masters (red icons)
- [ ] LOOT reports no critical errors
- [ ] xEdit filter shows no unresolved critical conflicts
- [ ] Game launches without CTD
- [ ] Campfire MCM appears (place campfire, build tent)
- [ ] Frostfall MCM appears (exposure meter visible in cold areas)
- [ ] Hunterborn MCM appears (kill animal → activate → skinning menu)
- [ ] Scarcity working (containers have less loot)
- [ ] Requiem perks and balance still function
- [ ] No duplicate survival systems (SMI fully disabled)
- [ ] Save game after 30+ min — no papyrus log spam
- [ ] Food/water/fatigue rates feel appropriate with timescale=12

---

## MCM Configuration

### Frostfall MCM
- Exposure rate: 1.5x (harsh)
- Max exposure time: Reduce for more lethal cold
- Warmth rating effectiveness: Reduce (clothing alone shouldn't save you)
- Enable season-based temperatures

### Campfire MCM
- Enable skill system
- Set fire warmth radius
- Configure tent/shelter options

### Hunterborn MCM
- Enable all features (skinning, processing, foraging)
- Dagger required for skinning: Yes
- Disable features that overlap with Immersive Hunting Animations

### Scarcity MCM
- Loot multiplier: 0.5x or lower
- Merchant restock: Reduce frequency
- Rare item chance: Decrease further

---

## Rollback Plan

If something breaks:

1. **Restore backup profile**:
   ```bash
   rm -rf "/mnt/2nd_NVME/Games/Skyrim/LoreRim/profiles/Ultra"
   cp -r "/mnt/2nd_NVME/Games/Skyrim/LoreRim/profiles/Ultra-BACKUP-presurvival" \
         "/mnt/2nd_NVME/Games/Skyrim/LoreRim/profiles/Ultra"
   ```
2. All original mods are just unchecked, not deleted — re-enable them
3. No original files were modified (only new files added + modlist/plugins.txt changes)
4. **Start a new game** after these changes (recommended)

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Frostfall + Requiem conflict | Medium | All-in-one Requiem patch + Wildlander proves it works |
| Scarcity leveled list overlap | Medium-High | Synthesis re-run + xEdit verification |
| Hunterborn papyrus script bloat | Low | Modern SSE handles it; Wildlander runs it fine |
| Breaking existing saves | High | Start a new game after changes |
| Campfire.esm load order | Low | ESM auto-sorts to top; well-tested |
| Needs drain too fast with timescale=12 | Medium | Adjust MCM rates, test early |
