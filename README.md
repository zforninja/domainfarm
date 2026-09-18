# FFXI Domain Invasion Auto-Farmer (DomainFarm)

**Author:** Zforninja
**Version:** 11.5
**Platform:** Final Fantasy XI (Windower 4)

A fully automated, state-machine-driven Lua addon for Windower 4 that continuously farms Domain Invasion across all three Escha zones: **Reisenjima**, **Escha - Zi'Tah**, and **Escha - Ru'Aun** — including the **Mireu** spawn.

The addon runs an 11-phase self-healing state machine that rotates through the zones, walks up to the Domain Invasion NPC and drives its menu natively (Elvorseal + warp-to-arena), summons Trusts, positions on the arena flank to avoid breath attacks, fights whichever DI target is up (zone dragon *or* Mireu), and warps out. It auto-corrects when rings are on cooldown, zones change unexpectedly, or the player dies.

As of **v11**, Superwarp is used for exactly one thing: the Home Point warps to Qufim Island and Misareaux Coast. Everything else — Dimensional Portal, Domain NPC menus, Undulating Confluence entry — is done with DomainFarm's own packet handling.

---

## 🌟 Key Features

- **Full 3-Zone Rotation:** Quetzalcoatl (Reisenjima) → Azi Dahaka (Escha - Zi'Tah) → Naga Raja (Escha - Ru'Aun) → repeat.
- **Mireu Support:** Mireu spawns **in place of** the zone dragon (exactly one of the two is up in a given visit). It's in every zone's target set, gets announced on the HUD, and is fought exactly like the dragon. When either dies the rotation advances immediately.
- **Native Escha menus (v11):** The Domain Invasion NPC (Affi / Dremi / Shiftrix) and the Undulating Confluence are approached and interacted with directly. Their menus are captured from incoming `0x032`/`0x034` packets and driven by packet sequences ported from Superwarp's `map/escha.lua`, waiting on the server's real `0x05C` acknowledgement between steps (v11.2).
- **Terrain-following approach (v11.1):** Phases 3 and 9 walk the known waypoint path first, then switch to a live find-and-interact on the NPC once it is in the entity table — with a fresh position snapshot every tick so the bot no longer "walks up and wiggles" on a stale distance.
- **Self-Healing State Machine:** If you manually warp, zone, die, or a ring is on cooldown, the bot re-derives the correct phase from where you physically are and resumes.
- **Superwarp only for Home Points:** `sw hp qufim island` / `sw hp misareaux coast` (explicit `hp` avoids Survival Guide ambiguity). Superwarp's own "No … found! Retrying…" chat lines are read to retry / fail fast instead of waiting on the watchdog.
- **Smart Combat Positioning:** Paths to the flank of each dragon using per-zone waypoints to keep Trusts out of frontal breath cleaves.
- **Corrected heading math (v11.5):** `heading_of()` now uses `-atan2(dy, dx)`, matching every working Windower movement/follow addon checked. The old positive `atan2` was a mirror-flipped heading — correct only due east/west, increasingly wrong elsewhere — and was the most likely cause of "attacking while facing away from the mob". The `vector` movement mode (default) was never affected because it passes raw `dx/dy` to `windower.ffxi.run()` without going through `heading_of()`.
- **Wider inventory scan (v11.5):** `item_in_inventory()` now uses `ipairs()` over the bag table (matching every real Windower addon) instead of a `for i=1,contents.max` loop that relied on a `.max` field `get_items()` doesn't actually return. Also checks Wardrobe 5–8 (bags 13–16) in addition to Wardrobe 1–4.
- **Face-then-engage (v11.3):** Turns to the mob, waits a tick, then engages — fixes the "attack on while not facing the mob" miss. The stuck-engage fallback faces first too.
- **Coordinate-Based Chase:** Steers with `windower.ffxi.run()` toward the mob's actual position — independent of the game's TargetLock setting.
- **Phantom Spawn Detection:** Filters by `valid_target` and `spawn_type` so only real, engageable dragons are targeted.
- **Auto-Trust Summoning:** Summons a configurable Trust lineup before every fight, with fallback alternates.
- **Zone Confirmation Gate + Post-Zone Settle:** No NPC or mob interaction until the zone ID matches what the phase expects and the 4-second settle window has passed.
- **Phase-Specific Watchdog Timers:** 1–3 minutes for rings/menus/approach, 20 minutes for the arena (dragon spawns can take 15+ minutes). Soft-recovers before stopping; the recovery budget refreshes on every zone change.
- **Stuck Detection:** Monitors position every 12 seconds during movement phases.
- **Death Recovery:** Detects death (status 2/3 only — never cutscenes), returns to Home Point, and resumes the rotation.
- **HUD:** Current status, target zone, phase, engaged target name, kill count, and any warnings.

---

## 📋 Prerequisites

1. **Superwarp Addon:** Must be installed and loaded — but **only** for the Home Point warps on the Zi'Tah and Ru'Aun legs (`sw hp qufim island`, `sw hp misareaux coast`). Elvorseal requests and Escha entry no longer go through it.
2. **Teleportation Rings:**
   - **Any one** of: `Dim. Ring (Dem)`, `Dim. Ring (Holla)`, or `Dim. Ring (Mea)` — each reaches a different Crag, all three have a Dimensional Portal to Reisenjima. The bot auto-detects which ring you have.
   - `Warp Ring` — returns to your Home Point after a Zi'Tah / Ru'Aun kill.
3. **Unlocked Home Points / Portals:**
   - Qufim Island Home Point #1 (route to Escha - Zi'Tah).
   - Misareaux Coast Home Point #1 (route to Escha - Ru'Aun).
   - The Dimensional Portal at whichever Crag your ring reaches (Dem, Holla, or Mea).
4. **Trusts:** The spells configured in `libs/df_trusts.lua` must be learned on your character.

---

## 🚀 Installation

1. Create the folder `addons/DomainFarm/` inside your Windower directory.
2. Copy `DomainFarm.lua` **and the whole `libs/` folder** into it. The addon `require`s the four `libs/df_*.lua` files and will not load without them:
   ```
   addons/DomainFarm/
   ├── DomainFarm.lua
   └── libs/
       ├── df_eschawarp.lua
       ├── df_trusts.lua
       ├── df_waypoints.lua
       └── df_zones.lua
   ```
3. In-game: `//lua load DomainFarm`

---

## ⚙️ Configuration

General settings live at the top of `DomainFarm.lua` in the `settings` table. Zone lists, waypoint paths and the Trust lineup moved into `libs/` in v11 (see the [Files](#-files) table).

### Rings
```lua
local settings = {
    -- The bot checks for each ring in order and uses the first one found.
    teleport_rings  = {'Dim. Ring (Dem)', 'Dim. Ring (Holla)', 'Dim. Ring (Mea)'},
    warp_ring       = 'Warp Ring',
```

### Superwarp Commands (Home Point warps only)
```lua
    sw_qufim        = 'sw hp qufim island',     -- explicit Home Point warp (avoids Survival Guide ambiguity)
    sw_misareaux    = 'sw hp misareaux coast',  -- explicit Home Point warp (avoids Survival Guide ambiguity)
```
`sw_elvorseal` and `sw_enter_escha` were removed in v11 — those interactions are native now.

### Ranges & Timing
```lua
    engage_range    = 7,       -- melee range check (yalms)
    waypoint_range  = 2,       -- waypoint arrival tolerance (yalms)
    npc_range       = 3,       -- interaction range for Dimensional Portal / Domain NPC / Confluence
    elvorseal_buff  = 603,     -- buff ID for Elvorseal
    elvorseal_retry = 60,      -- seconds between Elvorseal / "dragon not ready" retries
    elvorseal_max   = 5,       -- consecutive failures before giving up
    ring_timeout    = 120,     -- seconds before a ring phase is declared failed
    stuck_timeout   = 12,      -- seconds without movement progress = stuck
    zone_settle     = 4,       -- seconds to wait after arriving in a zone before touching entities
    movement_mode   = 'vector',-- 'vector' = windower.ffxi.run(dx, dy); 'heading' = run(radians)
```

### Bonus Targets
```lua
    bonus_targets   = {'Mireu'},   -- alternate DI spawns, fought like the dragon in every zone
```
`post_kill_linger` was removed in v11.4: Mireu spawns *instead of* the dragon, never after it, so there is nothing to wait for once the arena target dies.

### Resilience
```lua
    watchdog_recoveries = 2,    -- soft re-routes the watchdog may attempt before stopping (refreshed per zone change)
    unknown_zone_grace  = 30,   -- seconds in an unrecognized zone before escaping (0 = never)
    log_phases          = true, -- print every phase transition + reason to the chat log
}
```

### Trusts — `libs/df_trusts.lua`
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

### Zones — `libs/df_zones.lua`
Zone IDs are looked up by name from the `resources` library. `safe_zone_names` is the list of towns where ring / Superwarp phases may run (v11 added Aht Urhgan Whitegate, Nashmau, Tavnazian Safehold and Al Zahbi). If `//df start` ever warns `"<zone>" is not in safe_zone_names…`, add that zone here.

### Waypoints — `libs/df_waypoints.lua`
All paths: Zi'Tah / Ru'Aun zone-in → Domain NPC, Qufim / Misareaux Home Point → Undulating Confluence, and the per-arena flank positions. Use `//df mark` to capture coordinates when adjusting them.

---

## 🎮 Commands

All commands use `//domainfarm` (or the shorthand `//df`).

| Command | Description |
| :--- | :--- |
| `//df start` | Starts at **Reisenjima** (Quetzalcoatl). Uses a Dim. Ring to begin the loop. |
| `//df start zitah` | Starts at **Escha - Zi'Tah** (Azi Dahaka). Warps to Qufim to enter. |
| `//df start ruaun` | Starts at **Escha - Ru'Aun** (Naga Raja). Warps to Misareaux to enter. |
| `//df start` (inside Zi'Tah / Ru'Aun) | With no argument, the bot **adopts the DI zone you are standing in** instead of warping out to Reisenjima. |
| `//df stop` | Halts the bot, clears the active phase, and stops all movement. |
| `//df resume` | Restarts travel for the **current** target from wherever you are (use after a watchdog stop). |
| `//df status` | Prints: running/paused, target zone, phase (+ seconds in phase), current zone, last phase transition, watchdog recoveries used, any error. |
| `//df mark` | Prints your current X/Y coordinates to the chat log (for building waypoint paths). |
| `//df help` | Prints the command list. |

If the zone isn't known yet when you type `start` (right after logging in / zoning), the bot waits 2 seconds and retries instead of guessing.

---

## 🛠️ How It Works (The 11-Phase Loop)

### Normal Rotation

| Phase | Name | Watchdog | What Happens |
| :---: | :--- | :---: | :--- |
| **1** | Equipping / Using Teleport Ring | 120 s | Scans inventory for any Dimensional Ring, equips it, uses it. Also the escape phase from a wrong zone when the target is Reisenjima (the ring works from anywhere). |
| **2** | Navigating to Dimensional Portal | 120 s | At the Crag: walks to the Dimensional Portal, interacts, captures its menu from the incoming packet and selects Reisenjima (Option 0 → 2). |
| **3** | Approaching Domain Invasion NPC | 180 s | **All three zones.** Walks the zone's waypoint path (Zi'Tah / Ru'Aun), then finds Affi / Dremi / Shiftrix in the entity table and interacts within `npc_range`. The incoming `0x032`/`0x034` menu is captured into `state.domain_menu`. |
| **4** | Requesting Elvorseal / Warping to Arena | 60 s | Reads the dragon-up / Elvorseal-active bits from the captured menu. Dragon not up → cancels the menu and retries phase 3 after `elvorseal_retry` (stops after `elvorseal_max`). Otherwise fires the ported sequence: Option 14, then 8, 9, (9, 10 if you lack Elvorseal), 11, a same-zone `0x05C` move to the arena landing spot, Option 12 to close — each acked step waits for the server's `0x05C` (5 s fallback). |
| **5** | Verifying Elvorseal Buff | 1200 s | Confirms Buff ID 603 is active. If not, falls back to phase 3 for a retry. |
| **6** | Arena Combat & Trusts | 1200 s | Flank position, Trusts, scan for the zone dragon + Mireu (`valid_target` / `spawn_type` filtered). Faces the target, waits a tick, engages; coordinate-based chase. On kill → disengage → advance the rotation immediately. |
| **7** | Equipping / Using Warp Ring | 120 s | Disengages, equips and uses the Warp Ring to return to your Home Point. Also the escape phase from a wrong zone when the target is Zi'Tah / Ru'Aun. |
| **8** | Safe Zone - Superwarping (Home Point) | 120 s | `sw hp qufim island` or `sw hp misareaux coast`. Watches Superwarp's chat: "…found! Retrying…" waits, a terminal "No … found!" fails fast. |
| **9** | Approaching Undulating Confluence | 180 s | Walks the Qufim / Misareaux tunnel path, then finds the Confluence and interacts. Menu captured into `state.confluence_menu`. |
| **10** | Entering Escha | 60 s | Fires the ported enter sequence (`0x016` update, Option 0, Option 1 — fixed delays) and waits for the zone change. Back to phase 3. |

After Ru'Aun the rotation wraps back to phase 1 (Reisenjima).

### Emergency: Death Recovery

| Phase | Name | Watchdog | What Happens |
| :---: | :--- | :---: | :--- |
| **11** | Dead - Returning to Home Point | 300 s | Triggered by player death (status 2 or 3) from any phase. Injects the Home Point return dialog packet once (one-shot latch). Once alive and in a safe zone, resumes the rotation from the appropriate phase. |

### Safety Systems Active Every Tick

- **Zone confirmation gate** — no NPC/mob interaction unless the current zone ID matches what the phase expects.
- **Post-zone settle** — a 4-second cooldown after any zone change while the client loads its entity table.
- **Phase watchdog** — per-phase timeouts (table above). Timer refreshes on *real progress* (waypoint reached, closing distance). On trip: **soft recovery** re-derives the phase from where you physically are, up to `watchdog_recoveries` times — and that budget resets every time you actually change zones, so a hiccup in Qufim and another in Zi'Tah don't add up to a hard stop. `//df resume` picks it back up after a stop.
- **Stuck detection** — position progress checked every 12 seconds during movement.
- **Zone reality enforcement** — the router checks the current zone *against the current target* every tick. Wrong DI zone / crag / conflux → escape via **Dim. Ring** (target Reisenjima) or **Warp Ring** (target Zi'Tah / Ru'Aun), then restart travel. Unrecognized zones escape after `unknown_zone_grace` seconds.
- **Stale-callback guard** — every phase transition bumps a sequence generation; queued menu callbacks from an abandoned sequence (e.g. a watchdog recovery mid-menu) are dropped instead of firing into the wrong phase.
- **Phase transition log** — `Phase: A -> B (reason)` on every transition; the last one is also shown by `//df status`.

---

## 🧪 Testing

An offline test harness is included:

```bash
lua5.1 test_harness.lua
# or, with any newer Lua via lupa:
python3 -c "from lupa import LuaRuntime; LuaRuntime().execute(\"dofile('test_harness.lua')\")"
```

It stubs the Windower 4 environment (including Windower's `string:unpack('bN', …)` bit reader used by `df_eschawarp.lua`) and runs **28 scenarios** covering:
- Addon + `libs/` load, all commands, nil-guard checks
- Ring equip/use with missing inventory
- Menu packet handling (injected, blocked, valid)
- Combat chase (coordinate-based, no `maths` library dependency)
- Death detection and Home Point recovery; cutscene status ≠ death
- Zone settling and zone-gate enforcement
- Phase watchdogs (combat survives 400 s; soft-recovers at 1200 s, stops after the recovery budget; transit re-paths)
- Zone/target mismatch (target Reisenjima while standing in Zi'Tah) → **Dim. Ring** escape, no engage, never a dead phase
- `//df start` with no argument inside a DI zone adopts that zone
- Reisenjima: **no `sw ew` command is ever sent**; the bot interacts with Shiftrix natively (`0x01A`), and a captured Domain menu starts the native sequence with Option 14
- `//df resume` after a stop; unrecognized zone → ring escape after the grace period
- Kill → disengage → immediate rotation advance (no linger), for both the dragon and Mireu
- Sticky targeting (no ping-pong between candidates); Mireu-only spawn → engaged

> **Not verified against a live client** (please test in-game before relying on the bot):
> - `read_domain_status()` bit offsets (dragon-up / Elvorseal-active) in the Domain NPC menu parameters.
> - The full native packet flow for phases 2, 4 and 10 (ported from Superwarp's `map/escha.lua`; ack-waiting matches the source, but the client has not been observed end-to-end).
> - Superwarp's exact chat phrasing for the phase-8 "found!" / "Retrying" signals — if it doesn't match, the bot simply falls back to the watchdog.
> - Waypoint coordinates, arena landing spots, and engage/claim mechanics.

---

## 📦 Files

| File | Purpose |
| :--- | :--- |
| `DomainFarm.lua` | The addon: settings, state machine, router, phase handlers, events, commands. |
| `libs/df_eschawarp.lua` | Native Escha menu packet builders — `read_domain_status`, `build_domain_cancel`, `build_domain_sequence`, `build_enter_sequence`, NPC name sets, per-zone arena landing spots. Ported from Superwarp's `map/escha.lua` (Akaden, BSD-3-Clause, notice preserved). |
| `libs/df_zones.lua` | Zone IDs by name, safe / crag / conflux / DI zone sets, the 3-zone rotation table, `zone_name_of`. |
| `libs/df_waypoints.lua` | All waypoint paths and arena flank positions. |
| `libs/df_trusts.lua` | Trust lineup and `get_missing_trust`. |
| `test_harness.lua` | Offline smoke-test suite (optional, not needed in-game). |

---

## 📝 Changelog

### v11.5 (Current)
- **Fixed mirror-flipped heading.** `heading_of()` was computing `atan2(dy, dx)` — every working Windower movement/follow addon found uses `-atan2(dy, dx)` instead. The unnegated version produces a heading that's mirrored around the east-west axis: correct at 0° and 180°, increasingly wrong elsewhere. This almost certainly explains reports of "still attacking while facing away from the mob". The default `vector` movement mode (which passes `dx/dy` directly to `windower.ffxi.run()`) was never affected — only `turn()` calls (facing before engage, face-then-engage in v11.3) went through `heading_of()`.
- **Fixed inventory scan.** `item_in_inventory()` iterated with `for i = 1, (contents.max or 0)`, but `get_items()` doesn't return a `.max` field — every real Windower addon uses `ipairs()` over the bag table. Switched to `ipairs()`. Also widened the bag list to include Wardrobe 5–8 (bags 13–16) alongside inventory + Wardrobe 1–4, so rings in newer wardrobes are found. (Note: Wardrobe 5–8 availability depends on a known Windower/private-server inconsistency in client-side vs. server-side unlock detection; if a ring specifically in one of those four bags still isn't found, that's a limitation outside DomainFarm's control.)

### v11.4
- **Mireu spawns in place of the dragon, not alongside/after it.** The 45-second `post_kill_linger` scan (v10.2) was built on the wrong assumption and only added dead time to every visit. Removed: a kill now goes disengage → `advance_rotation()` immediately. Mireu stays in every zone's target set and is fought exactly like the dragon.

### v11.3
- **Face-then-engage.** The bot turned and sent `/attack on` in the same tick, so the client sometimes attacked while not yet facing the mob. Now: turn, wait one tick, then engage. The stuck-engage fallback faces first as well.

### v11.2
- **Ack-driven menu sequences.** Interacting with Affi (Zi'Tah) never warped to the arena: the Domain menu steps were fired on guessed fixed delays, and a later selection landing before the server had processed the previous one silently derailed the sequence. `run_action_queue()` now waits for the real incoming `0x05C` acknowledgement per step (mirroring `map/escha.lua`'s `wait_packet`), with a 5-second `ACK_TIMEOUT` fallback so a missing ack can't hang the bot.

### v11.1
- **Terrain-following approach restored.** Phase 3 (Zi'Tah / Ru'Aun) and phase 9 (Qufim / Misareaux) walk their waypoint paths first, then hand off to the dynamic find-and-interact once the NPC is in the entity table (`approach_via_waypoints_then_interact`). Straight-line pathing to the NPC from the zone-in point was catching on terrain.

### v11.0
- **Superwarp dependency reduced to Home Point warps.** `sw ew domain` and `sw ew enter` are gone; the Dimensional Portal, Domain Invasion NPC and Undulating Confluence are approached and interacted with natively, their menus captured from incoming `0x032`/`0x034` packets, and driven by sequences ported from Superwarp's `map/escha.lua` (Akaden, BSD-3-Clause). `sw hp …` stays on Superwarp on purpose — its Home Point fuzzy-matching / unlock-bit handling is too large to reimplement for two warps.
- **Uniform phase 3/4 for all three zones.** Reisenjima now goes through *Approaching Domain Invasion NPC* → *Requesting Elvorseal / Warping to Arena* like Zi'Tah and Ru'Aun (v10.5's Reisenjima-specific short-cut is no longer needed). Phases renamed accordingly; timeouts: 3 = 180 s, 4 = 60 s, 9 = 180 s, 10 = 60 s.
- **Split into `libs/`:** `df_zones.lua`, `df_waypoints.lua`, `df_trusts.lua`, `df_eschawarp.lua`. `safe_zone_names` gained Aht Urhgan Whitegate, Nashmau, Tavnazian Safehold and Al Zahbi; the "not in safe_zone_names" warning names the missing zone.
- **Fresh mob snapshot every tick** in the shared `approach_and_interact()` — fixes the "walks up to the NPC and wiggles" stale-distance bug.
- **Smarter escape:** `escape_phase()` picks the Dim. Ring when the target is Reisenjima (it works from anywhere) instead of detouring home on the Warp Ring first.
- **Watchdog recovery budget refreshes on every zone change**, so a multi-hop leg doesn't share one budget across town → conflux → Escha.
- **Phase 8 reads Superwarp's chat** ("found!" / "Retrying") to retry or fail fast; `//df start` retries in 2 s if the zone isn't known yet; stale action-queue callbacks are invalidated on phase change (`seq_gen`).
- Settings: added `npc_range`; removed `sw_elvorseal`, `sw_enter_escha`.

### v10.5
- **Fixed the "phase 3 in Reisenjima" dead end** — with the target set to Reisenjima but the character standing in Zi'Tah/Ru'Aun, the old router forced a phase with no Reisenjima handler and idled into the 300 s watchdog. The router now checks zone **against the target** and escapes when they disagree.
- **Watchdog soft recovery**, zone-aware `//df start`, new `//df resume`, `Phase: A -> B (reason)` logging, richer `//df status`, unrecognized-zone fallback.

### v10.4
- **Multi-ring support** — any of `Dim. Ring (Dem)`, `Dim. Ring (Holla)`, `Dim. Ring (Mea)`; the first one found is used.

### v10.3
- Home Point warps use `sw hp <zone>` to avoid Survival Guide ambiguity; Escha entry via `sw ew enter` (since replaced natively in v11.0).

### v10.2
- Mireu multi-target support (`bonus_targets`, sticky targeting, HUD target/kill display), zone confirmation gate, post-zone settle delay, phase-specific watchdogs, coordinate-based chase, dynamic menu automation, one-shot death latch, stuck detection, offline harness.

### v10.0
- Full hardened rewrite addressing 34 code-review issues; removed the never-loaded `maths` dependency; nil-guards everywhere; centralized `set_phase`; ID-based zone routing.

### v8.2 (Original)
- Initial 10-phase state machine with 3-zone rotation.

---

## 📄 Attribution

`libs/df_eschawarp.lua` contains packet sequences ported from [Superwarp](https://github.com/AkadenTK/superwarp) (`map/escha.lua`) by Akaden, used under the BSD-3-Clause license. The original copyright notice is preserved in that file.

---

## ⚠️ Disclaimer

This addon automates gameplay mechanics in Final Fantasy XI. Use at your own risk. The author is not responsible for any account actions, bans, or penalties incurred from the use of this software. Please respect the server and other players.
