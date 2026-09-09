# FFXI Domain Invasion Auto-Farmer (DomainFarm)

**Author:** Zforninja
**Version:** 10.5
**Platform:** Final Fantasy XI (Windower 4)

A fully automated, state-machine-driven Lua addon for Windower 4 that continuously farms Domain Invasion across all three Escha zones: **Reisenjima**, **Escha - Zi'Tah**, and **Escha - Ru'Aun** — including the rare **Mireu** spawn.

The addon runs an 11-phase self-healing state machine that rotates through the zones, acquires Elvorseals, summons Trusts, positions on the arena flank to avoid breath attacks, fights every valid target (zone boss + Mireu), and warps out safely. It auto-corrects when rings are on cooldown, zones change unexpectedly, or the player dies.

---

## 🌟 Key Features

- **Full 3-Zone Rotation:** Cycles through Quetzalcoatl (Reisenjima) → Azi Dahaka (Escha - Zi'Tah) → Naga Raja (Escha - Ru'Aun) → repeat.
- **Mireu Support:** Mireu can spawn in any of the three arenas. The bot detects it automatically, announces it on the HUD, and fights it alongside (or instead of) the zone boss. A 45-second post-kill linger scan ensures Mireu isn't missed if it appears after the primary boss dies.
- **Self-Healing State Machine:** If you manually warp, zone, die, or your ring is on cooldown, the bot detects the new zone and resumes the correct phase without breaking.
- **Superwarp Integration:** Uses `//sw` commands for Elvorseal requests (`sw ew domain`), explicit Home Point warps (`sw hp qufim island`, `sw hp misareaux coast`) to avoid Survival Guide ambiguity, and Escha entry (`sw ew enter`) per the [Superwarp documentation](https://github.com/AkadenTK/superwarp).
- **Smart Combat Positioning:** Paths to the flank of each dragon using per-zone waypoints to protect Trusts from frontal breath cleaves.
- **Coordinate-Based Chase:** Steers toward the mob's actual position using `windower.ffxi.run()` — works regardless of the game's TargetLock setting.
- **Phantom Spawn Detection:** Filters by `valid_target` and `spawn_type` to ensure only real, engageable dragons are targeted.
- **Auto-Trust Summoning:** Summons a configurable Trust lineup before every fight, with fallback alternates.
- **Zone Confirmation Gate:** No NPC or mob interaction until the bot confirms it's in the correct zone by ID — prevents interacting with the wrong entities during zone transitions.
- **Post-Zone Settle Delay:** Waits 4 seconds after zoning for the entity table to populate before scanning for NPCs or mobs.
- **Phase-Specific Watchdog Timers:** 2 minutes for menus/rings, 5 minutes for transit, 20 minutes for combat (dragon spawns can take 15+ minutes).
- **Stuck Detection:** Monitors position every 12 seconds during movement phases; flags geometry snags.
- **Death Recovery:** Detects death (status 2/3 only — never cutscenes), returns to Home Point, and resumes the rotation.
- **HUD:** Displays current status, target zone, phase, engaged target name, kill count, and any warnings.

---

## 📋 Prerequisites

1. **Superwarp Addon:** Must be installed and loaded — the bot relies on it for Elvorseal requests and inter-zone travel.
2. **Teleportation Rings:**
   - **Any one** of: `Dim. Ring (Dem)`, `Dim. Ring (Holla)`, or `Dim. Ring (Mea)` — each reaches a different Crag, but all three have a Dimensional Portal to Reisenjima. The bot auto-detects which ring you have and uses it.
   - `Warp Ring` — returns to a safe zone / Home Point after each kill.
3. **Unlocked Waypoints:**
   - Qufim Island Home Point #1 (route to Escha - Zi'Tah).
   - Misareaux Coast Home Point #1 (route to Escha - Ru'Aun).
   - The Dimensional Portal at whichever Crag your ring reaches (Dem, Holla, or Mea).
4. **Trusts:** The spells configured in `trust_list` must be learned on your character.

---

## 🚀 Installation

1. Create the folder `addons/DomainFarm/` inside your Windower directory (if it doesn't exist).
2. Download `DomainFarm.lua` and place it in that folder.
3. In-game, load it with: `//lua load DomainFarm`

---

## ⚙️ Configuration

Open `DomainFarm.lua` in a text editor. All configurable values are at the top in the `settings` table:

### Rings
```lua
local settings = {
    -- The bot checks for each ring in order and uses the first one found.
    teleport_rings  = {'Dim. Ring (Dem)', 'Dim. Ring (Holla)', 'Dim. Ring (Mea)'},
    warp_ring       = 'Warp Ring',         -- ring to return to a safe zone after a kill
}
```

### Superwarp Commands
```lua
    sw_elvorseal    = 'sw ew domain',          -- request Elvorseal at the Eschan Portal
    sw_qufim        = 'sw hp qufim island',    -- explicit HP warp (avoids Survival Guide ambiguity)
    sw_misareaux    = 'sw hp misareaux coast',  -- explicit HP warp (avoids Survival Guide ambiguity)
    sw_enter_escha  = 'sw ew enter',            -- enter Escha via Eschan portal (per Superwarp docs)
```

### Trusts
```lua
local trust_list = {
    {spell = 'Ulmia',       alt = 'Arciela II'},
    {spell = 'Qultada',     alt = nil},
    {spell = 'Koru-Moru',   alt = nil},
    {spell = 'Joachim',     alt = 'Lilisette'},
    {spell = 'Sylvie (UC)', alt = 'Prishe II'},
}
```
Each entry has a primary `spell` and an optional `alt` fallback if the primary is unavailable.

### Bonus Targets
```lua
    bonus_targets    = {'Mireu'},          -- additional DI targets to fight in every zone
    post_kill_linger = 45,                 -- seconds to scan for another target after a kill
```
Add or remove names from `bonus_targets` to control which extra spawns the bot will engage.

### Timing & Thresholds
```lua
    engage_range    = 7,                   -- melee range (yalms)
    waypoint_range  = 2,                   -- waypoint arrival tolerance (yalms)
    elvorseal_buff  = 603,                 -- buff ID for Elvorseal
    elvorseal_retry = 60,                  -- seconds between Elvorseal retries
    elvorseal_max   = 5,                   -- consecutive failures before stopping
    stuck_timeout   = 12,                  -- seconds without movement = stuck
    zone_settle     = 4,                   -- seconds to wait after zoning before touching entities
    -- Resilience (v10.5)
    watchdog_recoveries = 2,               -- soft re-routes the watchdog may attempt before stopping
    unknown_zone_grace  = 30,              -- seconds in an unrecognized zone before warping home (0 = never)
    log_phases          = true,            -- print every phase transition + reason to the chat log
```

---

## 🎮 Commands

All commands use `//domainfarm` (or the shorthand `//df`).

| Command | Description |
| :--- | :--- |
| `//df start` | Starts at **Reisenjima** (Quetzalcoatl). Uses the Teleport Ring to begin the loop. |
| `//df start zitah` | Starts at **Escha - Zi'Tah** (Azi Dahaka). Warps to Qufim to enter. |
| `//df start ruaun` | Starts at **Escha - Ru'Aun** (Naga Raja). Warps to Misareaux to enter. |
| `//df start` (inside Zi'Tah / Ru'Aun) | v10.5: with no argument, the bot **adopts the DI zone you are standing in** instead of warping out to Reisenjima. |
| `//df stop` | Halts the bot, clears the active phase, and stops all movement. |
| `//df resume` | v10.5: restarts travel for the **current** target from wherever you are (use after a watchdog stop). |
| `//df status` | Prints the current state: running/paused, target zone, phase (+ seconds in phase), current zone, last phase transition, watchdog recoveries used, and any error. |
| `//df mark` | Prints your current X/Y coordinates to the chat log (for building waypoint paths). |
| `//df help` | Prints the command list. |

---

## 🛠️ How It Works (The 11-Phase Loop)

### Normal Rotation

| Phase | Name | What Happens |
| :---: | :--- | :--- |
| **1** | Teleport Ring | Scans inventory for any Dimensional Ring (Dem, Holla, or Mea), picks the first one found, equips it, and uses it. Logs which ring was selected. |
| **2** | Dimensional Portal | Arrives at the Crag zone. Walks to the Dimensional Portal NPC and injects menu packets to enter Reisenjima. |
| **3** | Path to Eschan Portal | Walks waypoints from the zone-in point to the Eschan Portal NPC. |
| **4** | Request Elvorseal | Sends `//sw ew domain` to request the Elvorseal buff. Retries up to 5 times at 60-second intervals. |
| **5** | Verify Elvorseal | Confirms Buff ID 603 is active. If rejected, falls back to Phase 4 for a retry. |
| **6** | Arena Combat | Positions on the flank, summons Trusts, scans for the zone boss + Mireu. Engages any valid target using coordinate-based chase. After each kill, lingers 45 seconds scanning for additional targets. Only advances when the arena is clear. HUD shows target name and kill count. |
| **7** | Warp Ring | Disengages, equips and uses the Warp Ring to return to a safe zone. |
| **8** | Superwarp Transit | From the safe zone, issues `//sw hp qufim island` or `//sw hp misareaux coast` to reach the next zone's staging area. Uses explicit `hp` prefix to avoid Survival Guide ambiguity. |
| **9** | Path to Confluence | Walks waypoints through the tunnel to the Undulating Confluence / Eschan Portal. |
| **10** | Enter Escha | Issues `//sw ew enter` to zone into the next Escha area. Returns to Phase 3. |

After completing Ru'Aun, the rotation wraps back to Phase 1 (Reisenjima).

### Emergency: Death Recovery

| Phase | Name | What Happens |
| :---: | :--- | :--- |
| **11** | Dead / Home Point | Triggered by player death (status 2 or 3) from any phase. Injects the Home Point return dialog packet. Once alive and in a safe zone, resumes the rotation from the appropriate phase. Uses a one-shot latch so the packet is only sent once per death. |

### Safety Systems Active Every Tick

- **Zone confirmation gate** — the bot will not touch NPCs or mobs unless the current zone ID matches what the phase expects.
- **Post-zone settle** — after any zone change, a 4-second cooldown prevents entity interaction while the client loads.
- **Phase watchdog** — each phase has a timeout (2 / 5 / 20 min depending on the phase type). The timer is refreshed by *real progress* (a waypoint reached, closing distance on the portal), not just by phase changes. When it trips, the bot first performs a **soft recovery**: it re-derives the phase from where you physically are (town → restart travel; target zone → re-request Elvorseal / re-path; anywhere else → Warp Ring home). Only after `watchdog_recoveries` failed recoveries does it stop, and `//df resume` picks it back up.
- **Stuck detection** — checks position progress every 12 seconds during movement; flags geometry snags.
- **Zone reality enforcement** — every tick, the router checks the current zone *against the current target*, not just against the phase. Standing in a DI zone, crag or conflux that doesn't belong to the current target → Warp Ring home and restart travel. Reisenjima never enters the "Pathing to Eschan Portal" phase (it has no portal path). Phase 1 vs 8 (Dim. Ring vs Superwarp) is corrected in town if the rotation index says otherwise. Unrecognized zones warp home after `unknown_zone_grace` seconds instead of idling into the watchdog.
- **Phase transition log** — every transition prints `Phase: A -> B (reason)` so a stall can be diagnosed from the chat log; the last transition is also shown by `//df status`.

---

## 🧪 Testing

An offline test harness is included:

```bash
lua5.1 test_harness.lua
```

It stubs the Windower 4 environment and runs 28 scenarios covering:
- Addon load, all commands, nil-guard checks
- Ring equip/use with missing inventory
- Menu packet handling (injected, blocked, valid)
- Combat chase (coordinate-based, no `maths` library dependency)
- Death detection and Home Point recovery
- Cutscene status ≠ death (no false triggers)
- Zone settling and zone-gate enforcement
- Coordinate-based chase vector validation
- Phase watchdogs (combat survives 400s; soft-recovers at 1200s, stops after the recovery budget; transit re-paths at 300s)
- Zone/target mismatch (target Reisenjima while standing in Zi'Tah) → Warp Ring escape, never a dead phase
- `//df start` with no argument inside a DI zone adopts that zone
- Reisenjima goes straight to the Elvorseal request (never the portal-pathing phase)
- `//df resume` after a stop; unrecognized zone → warp home after the grace period
- Mireu appearing after a primary kill → engaged
- Post-kill linger expiry → rotation advance
- Sticky targeting when both boss and Mireu are alive
- Mireu-only spawn → engaged

> **Note:** Live packet behavior, actual Superwarp command strings, waypoint coordinates, and engage/claim mechanics cannot be verified offline. Please test in-game before relying on the bot.

---

## 📦 Files

| File | Purpose |
| :--- | :--- |
| `DomainFarm.lua` | The addon — drop into `addons/DomainFarm/`. |
| `test_harness.lua` | Offline smoke-test suite (optional, not needed in-game). |

---

## 📝 Changelog

### v10.5 (Current)
- **Fixed the "phase 3 in Reisenjima" dead end** — with the target set to Reisenjima but the character standing in Zi'Tah/Ru'Aun (e.g. `//df start` after finishing a previous session there), the old router forced *Pathing to Eschan Portal*, a phase that has no handler for Reisenjima. The bot then idled until the 300 s watchdog stopped it. The router now checks zone **against the target** and warps home when they disagree; the phase-3 handler also self-corrects to the Elvorseal request for Reisenjima.
- **Watchdog soft recovery** — a tripped watchdog re-derives the phase from physical reality (up to `watchdog_recoveries` times) before stopping. Progress inside a phase (waypoint reached, closing on the portal) refreshes the timer.
- **Zone-aware `//df start` / new `//df resume`** — no-arg start adopts the DI zone you are in; `resume` restarts travel for the current target from anywhere. Start/resume/recovery all use one routing function, so there is a single source of truth for "which phase can make progress from here".
- **Diagnostics** — `Phase: A -> B (reason)` log lines (toggle `log_phases`), richer `//df status`, stale HUD notes ("Zone settling...") cleared on stop.
- **Unrecognized zone fallback** — warps home after `unknown_zone_grace` seconds instead of waiting for the watchdog.
- Harness: 28 scenarios (5 new); runs under Lua 5.1 or newer interpreters (`math.atan2` shim is harness-only).

### v10.4
- **Multi-ring support** — the bot now searches inventory for any of the three Dimensional Rings (`Dim. Ring (Dem)`, `Dim. Ring (Holla)`, `Dim. Ring (Mea)`) and uses the first one found. No more hardcoding a single ring — works with whichever ring(s) you have. Re-scans each cycle in case charges change.

### v10.3
- **Superwarp command fix** — Home Point warps now use `sw hp <zone>` (e.g., `sw hp qufim island`) to avoid ambiguity when a Survival Guide and HP are near each other. Escha entry now uses `sw ew enter` per [Superwarp documentation](https://github.com/AkadenTK/superwarp), eliminating lockups at Undulating Confluences and telepoints.

### v10.2
- **Mireu multi-target support** — `bonus_targets` list, sticky targeting, 45-second post-kill linger scan, HUD target/kill display.
- **Zone confirmation gate** — no entity interaction until the correct zone ID is confirmed.
- **Post-zone settle delay** (4 seconds) — prevents nil entity lookups right after zoning.
- **Phase-specific watchdog timers** — 2 min (menus), 5 min (transit), 20 min (combat).
- **Coordinate-based chase** — uses `windower.ffxi.run()` with mob position vectors; TargetLock-independent.
- **Dynamic menu automation** — reads menu/zone IDs from server packets instead of hardcoded values.
- **One-shot death latch** — status 2/3 only; no false triggers during cutscenes.
- **Movement stuck detection** on all pathing phases.
- **Offline test harness** with 23 scenarios.

### v10.0
- Full hardened rewrite addressing 34 issues from code review (5 Critical, 8 High, 21 Medium/Low).
- Removed dependency on the never-loaded `maths` library.
- Nil-guards on every API call. Centralized `set_phase` transitions.
- ID-based zone routing. Proper `party1_count` trust summoning.

### v8.2 (Original)
- Initial 10-phase state machine with 3-zone rotation.

---

## ⚠️ Disclaimer

This addon automates gameplay mechanics in Final Fantasy XI. Use at your own risk. The author is not responsible for any account actions, bans, or penalties incurred from the use of this software. Please respect the server and other players.
