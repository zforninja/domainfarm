--[[
    DomainFarm v11.5
    Automated Domain Invasion farming for Windower 4.

    Rotation: Reisenjima (Quetzalcoatl) -> Escha-Zi'Tah (Azi Dahaka)
              -> Escha-Ru'Aun (Naga Raja) -> repeat.

    Alternate spawn: Mireu can appear in place of a zone's dragon (not
    alongside or after it -- exactly one of the two is ever up per visit),
    so it's added to every zone's target list and fought the same way the
    dragon would be (see settings.bonus_targets).

    Dependencies:
      - Windower 4's stock 'packets' / 'resources' / 'texts' libraries.
      - libs/df_zones.lua, libs/df_waypoints.lua, libs/df_trusts.lua,
        libs/df_eschawarp.lua (ship these alongside this file, under the
        addon's own libs/ folder).
      - The Superwarp addon must be loaded, but ONLY for Home Point warps
        (phase 8, used when the target is Escha-Zi'Tah/Ru'Aun and we're
        starting from a town). Everything else -- the Dimensional Portal to
        Reisenjima, requesting Elvorseal, entering Escha from the conflux --
        is done natively with our own packets. See "v11: dropped the
        Superwarp dependency for..." below for why Home Point warping alone
        was deliberately NOT brought in-house.

    v11.5: two fixes, both cross-checked against real working Windower
    addon source rather than guessed:
      - heading_of() was computing atan2(dy, dx) directly. Checked against
        several independent, working Windower movement/follow addons found
        in the wild -- they all negate this (-atan2(dy, dx)). The unnegated
        version produces a mirror-flipped heading, correct only when the
        target is due east or west -- almost certainly why the character
        would sometimes keep attacking while facing away from the mob.
        run_towards()'s default 'vector' mode was never affected (it passes
        dx/dy straight to windower.ffxi.run(), never through heading_of()),
        which is why chasing/approaching was never reported as wrong -- only
        facing (which always goes through turn(), and so always through
        heading_of()) was.
      - item_in_inventory() iterated a bag's contents as `for i = 1,
        (contents.max or 0) do contents[i] ... end`. Every real Windower
        addon that scans a bag does it with ipairs(get_items(bag)) instead;
        none reference a `.max` field, which doesn't appear to actually
        exist on what get_items() returns. Switched to ipairs(), and widened
        the bag list to include Wardrobe 5-8 (13-16), not just Wardrobe 1-4
        (0, 8, 10-12). Note: there's a documented Windower/private-server
        inconsistency in how Wardrobe 5-8 get detected at all (different
        client-side vs. server-side logic) -- if a ring specifically in one
        of those four is still not found, that's a known limitation outside
        what this addon can work around.

    v11.4: Mireu doesn't spawn after a zone's dragon is killed -- it spawns
    in place of it (exactly one of the two is ever up per visit). The old
    post-kill logic didn't know that: it waited settings.post_kill_linger
    (45s) after every kill scanning for a second target that was never
    coming. Removed that wait entirely -- confirming a kill now disengages
    (if needed) and calls advance_rotation() immediately. Targeting itself
    was already correct (Mireu was already in every zone's target set and
    would be found and engaged whether it or the dragon spawned); only the
    post-kill wait was wrong.

    v11.3: the initial engage packet used to fire in the same tick as the
    turn-to-face command. windower.ffxi.turn() needs at least a moment to
    actually rotate the character, so engaging immediately after could catch
    the client still mid-turn (reported: not always facing the mob when
    engaging). engage_when_facing_ready() now turns, waits one tick, then
    engages. The "stuck, engage from here" fallback had a second version of
    the same gap -- it never called face_towards() at all before engaging --
    now fixed the same way.

    v11.2: build_domain_sequence()'s steps (libs/df_eschawarp.lua) now carry
    a wait_ack flag matching map/escha.lua's wait_packet=0x05C exactly --
    every step except Option Index 14 needs the real acknowledgement, not a
    guessed delay. run_action_queue() (replacing the old fixed-delay
    run_packet_sequence()) waits for the actual incoming 0x05C before firing
    the next menu selection, falling back to a 5s timeout if one never
    arrives. This was the reported bug: interacting with Affi in Escha-
    Zi'Tah never warped to the arena, because a later selection was firing
    before the server had processed the previous one. build_enter_sequence()
    (phase 10) is unchanged -- the source shows no such dependency there.

    v11.1: restored the terrain-following waypoint paths to the Domain
    Invasion NPC (zitah_waypoints/ruaun_waypoints) and the Undulating
    Confluence (q_waypoints/m_waypoints) that v11.0 had dropped in favor of
    a pure straight-line walk to the live entity. That was wrong: those
    paths exist to route around real terrain (a wall, a ledge) between the
    zone entrance and the NPC, and a straight vector can't do that -- it
    just walks into whatever's in the way and sits there. Phases 3 and 9 now
    walk the fixed path first, THEN do the dynamic find-and-interact for the
    last stretch (see approach_via_waypoints_then_interact()) -- keeping
    both fixes rather than trading one for the other.

    v11: dropped the Superwarp dependency for Elvorseal requests and Escha
    entry (previously "sw ew domain" / "sw ew enter"), replacing them with
    native packet sequences ported from Superwarp's own map/escha.lua
    (Akaden, BSD-3-Clause; see libs/df_eschawarp.lua for the specific lines
    each function is based on, and the license notice preserved there).
    This was reading Superwarp's own do_sub_cmd(): it requires the player be
    within 6 yalms of the target NPC and does NOT walk there itself -- so
    DomainFarm's old fixed waypoints only ever solved "am I close enough",
    never "how do I get there" -- both still matter, see v11.1 above.
    Home Point warping (phase 8) was deliberately left on Superwarp: it's
    Superwarp's largest subsystem (fuzzy name matching against every home
    point in the game, character-specific unlock-bit checks), rebuilding it
    natively is a much worse cost/benefit trade than the Escha portal work
    was, and Superwarp already gets that logic right and keeps it patched.

    v11 also splits static data and the new Escha packet logic out into
    libs/ so this file only holds DomainFarm's own state machine:
      libs/df_zones.lua      - zone ID resolution, safe/portal/conflux
                                zone sets, the rotation table
      libs/df_waypoints.lua  - all waypoint paths: terrain-following walks
                                to the Domain NPC / Undulating Confluence,
                                and the post-teleport arena landing walks
      libs/df_trusts.lua     - trust lineup + missing-trust lookup
      libs/df_eschawarp.lua  - native Elvorseal/Escha-entry packet builders

    Everything documented in prior passes remains fixed:
      - all nil-dereference crash sites guarded (player/me/party/res lookups)
      - menu automation reads Menu ID / Zone from the parsed packet instead
        of hardcoding it, ignores injected chunks, blocks the client menu
      - death detected only on status 2/3 (never cutscenes), one-shot latch
      - disengage before ring/warp phases
      - per-phase watchdog timeouts, with soft-recovery (2 attempts,
        refreshed on every actual zone change, not just once per rotation
        leg) before a hard stop
      - progress-aware watchdog (mark_progress()) for approach/pathing phases
      - zone-vs-target mismatch resolved by a single "reality router"
        (enforce_zone_reality) that runs every tick before phase dispatch
      - zone routing by zone ID, not by name-string comparison at runtime
      - party fullness via party1_count, not the p5 proxy
      - explicit stop/pause on logout; movement halted on unload
      - zone confirmation gate, post-zone settling window, phase-transition
        log, //df resume, //df start adopts the DI zone you're standing in
      - Superwarp's own chat output (phase 8) is read via 'incoming text' so
        DomainFarm reacts to what Superwarp actually reports instead of only
        a fixed timer
]]

_addon.name     = 'DomainFarm'
_addon.author   = 'Zforninja (hardened rewrite)'
_addon.version  = '11.5'
_addon.commands = {'domainfarm', 'df'}

require('logger')
local packets = require('packets')
local res     = require('resources')

local zones     = require('libs/df_zones')
local waypoints = require('libs/df_waypoints')
local trusts    = require('libs/df_trusts')
local eschawarp = require('libs/df_eschawarp')

-- Optional HUD
local texts_success, texts = pcall(require, 'texts')

-- ==========================================================================
-- CONFIGURATION
-- ==========================================================================
local settings = {
    -- Any Dimensional Ring works — all three crags have a Dimensional Portal.
    -- The bot checks inventory for each ring in order and uses the first one found.
    teleport_rings  = {'Dim. Ring (Dem)', 'Dim. Ring (Holla)', 'Dim. Ring (Mea)'},
    warp_ring       = 'Warp Ring',
    -- Superwarp command strings for the ONE thing still routed through it:
    -- Home Point warps to the conflux zones (adjust if your version differs).
    sw_qufim        = 'sw hp qufim island',     -- explicit Home Point warp (avoids Survival Guide ambiguity)
    sw_misareaux    = 'sw hp misareaux coast',  -- explicit Home Point warp (avoids Survival Guide ambiguity)
    engage_range    = 7,                   -- melee range check (yalms)
    waypoint_range  = 2,                   -- waypoint arrival tolerance (yalms)
    npc_range       = 3,                   -- interaction range for Dimensional Portal / Domain NPC / Confluence
    elvorseal_buff  = 603,                 -- buff ID for Elvorseal
    elvorseal_retry = 60,                  -- seconds between Elvorseal retries
    elvorseal_max   = 5,                   -- consecutive failures before giving up
    ring_timeout    = 120,                 -- seconds before a ring phase is declared failed
    stuck_timeout   = 12,                  -- seconds without movement progress = stuck
    zone_settle     = 4,                   -- seconds to wait after arriving in a zone before touching entities
    movement_mode   = 'vector',            -- 'vector' = windower.ffxi.run(dx, dy); 'heading' = run(radians)
    -- Alternate Domain Invasion spawns: Mireu can appear in place of the
    -- zone's dragon (not alongside or after it -- exactly one of the two is
    -- ever up in a given visit), so it's added to every zone's target set
    -- and fought the same way the dragon would be.
    bonus_targets   = {'Mireu'},
    -- Resilience
    watchdog_recoveries = 2,               -- soft re-routes the watchdog may attempt before stopping (refreshed per zone change)
    unknown_zone_grace  = 30,              -- seconds to sit in an unrecognized zone before warping home (0 = never)
    log_phases          = true,            -- print every phase transition and its reason to the chat log
}

-- Phase-specific watchdog timeouts (seconds). Combat/arena phases must tolerate
-- the 15+ minute wait for a Domain Invasion boss to spawn; approach/transit
-- phases are stuck much sooner.
local PHASE_TIMEOUTS = {
    [1]  = 120,    -- teleport ring
    [2]  = 120,    -- dimensional portal menu
    [3]  = 180,    -- approaching the Domain Invasion NPC
    [4]  = 60,     -- processing its menu (Elvorseal + warp-to-arena sequence)
    [5]  = 1200,   -- verifying elvorseal (arena, dragon may not be up yet)
    [6]  = 1200,   -- combat / waiting for boss spawn
    [7]  = 120,    -- warp ring
    [8]  = 120,    -- superwarp home point warp
    [9]  = 180,    -- approaching the Undulating Confluence
    [10] = 60,     -- processing its menu (enter Escha)
    [11] = 300,    -- dead / home point
}

-- ==========================================================================
-- ZONE / ROTATION DATA (libs/df_zones.lua) + ARENA WAYPOINTS (libs/df_waypoints.lua)
-- ==========================================================================
local ZONES            = zones.ZONES
local safe_zone_ids    = zones.safe_zone_ids
local portal_zone_ids  = zones.portal_zone_ids
local conflux_zone_ids = zones.conflux_zone_ids
local rotation         = zones.rotation
local zone_name_of     = zones.zone_name_of

local zitah_arena_wps = waypoints.zitah_arena_wps
local ruaun_arena_wps = waypoints.ruaun_arena_wps
local reisen_arena    = waypoints.reisen_arena
local zitah_waypoints = waypoints.zitah_waypoints   -- zone entrance -> Domain NPC (terrain)
local ruaun_waypoints = waypoints.ruaun_waypoints   -- zone entrance -> Domain NPC (terrain)
local q_waypoints     = waypoints.q_waypoints       -- zone entrance -> Undulating Confluence (terrain)
local m_waypoints     = waypoints.m_waypoints       -- zone entrance -> Undulating Confluence (terrain)

-- Arena anchor per rotation index (used for the target scan radius). For
-- Zi'Tah / Ru'Aun the anchor is the final arena waypoint.
rotation[1].arena = reisen_arena
rotation[2].arena = zitah_arena_wps[#zitah_arena_wps]
rotation[3].arena = ruaun_arena_wps[#ruaun_arena_wps]

-- Build each zone's full target list: primary boss + every bonus target
-- (Mireu). `targets` is a name->true set for O(1) lookups during mob scans.
for _, entry in pairs(rotation) do
    entry.targets = {[entry.boss] = true}
    for _, name in ipairs(settings.bonus_targets) do
        entry.targets[name] = true
    end
end

local get_missing_trust = trusts.get_missing_trust

-- ==========================================================================
-- STATE
-- ==========================================================================
local PHASE_NAMES = {
    [0]  = 'Idle / Stopped',
    [1]  = 'Equipping / Using Teleport Ring',
    [2]  = 'Navigating to Dimensional Portal',
    [3]  = 'Approaching Domain Invasion NPC',
    [4]  = 'Requesting Elvorseal / Warping to Arena',
    [5]  = 'Verifying Elvorseal Buff',
    [6]  = 'Arena Combat & Trusts',
    [7]  = 'Equipping / Using Warp Ring',
    [8]  = 'Safe Zone - Superwarping (Home Point)',
    [9]  = 'Approaching Undulating Confluence',
    [10] = 'Entering Escha',
    [11] = 'Dead - Returning to Home Point',
}

local state = {
    running            = false,
    phase              = 0,
    zone_index         = 1,
    waypoint_index     = 1,
    fighting           = false,
    boss_id            = nil,          -- cached entity ID of the CURRENT target (boss or Mireu)
    boss_missing_since = nil,          -- os.time() when the target vanished from tracking
    target_name        = nil,          -- name of the current target (HUD)
    pending_advance    = false,        -- kill confirmed; disengaging before advance_rotation()
    kills              = 0,            -- kills this arena visit
    bonus_seen         = {},           -- alternate-spawn names already announced this visit
    arena_positioned   = false,
    facing_settled     = false,        -- one-tick turn-then-wait latch before the first engage packet
    approach_npc       = nil,          -- entity snapshot for phase 2/3/9's shared approach-and-interact
    approach_best_dist = nil,          -- closest approach so far (watchdog progress)
    wp_path_done       = false,        -- phase 3/9: terrain-following waypoint stage complete
    domain_menu        = nil,          -- {npc, zone, menu_id, menu_params} captured in phase 3, consumed in phase 4
    confluence_menu    = nil,          -- {npc, zone, menu_id} captured in phase 9, consumed in phase 10
    elvorseal_sent_at  = nil,          -- os.time() the Elvorseal sequence completed (phase 5 anchor)
    elvorseal_fails    = 0,
    ring_started_at    = nil,          -- os.time() when the current ring phase began
    ring_equip_sent    = false,
    selected_tp_ring   = nil,          -- which Dim. Ring was picked for this cycle
    phase_started_at   = os.time(),    -- watchdog anchor
    death_latched      = false,        -- home-point packet sent once per death
    sw_attempts        = 0,            -- superwarp retry counter for phase 8
    last_pos           = nil,          -- {x, y, t} for stuck detection
    fail_reason        = nil,          -- surfaced on the HUD
    last_unhandled_zone = nil,
    last_seen_zone     = nil,          -- zone ID observed on the previous tick
    settle_until       = nil,          -- os.time() before which entity interaction is forbidden
    hud_note           = nil,          -- transient status line (settling / zone gate)
    watchdog_recoveries = 0,           -- soft recoveries used since the last successful zone change
    last_recovery_zone = nil,          -- zone ID the recovery budget was last refreshed for
    unknown_zone_since = nil,          -- os.time() we first saw an unrecognized zone
    last_transition    = nil,          -- "phase A -> B (reason)" for //df status
    sw_signal          = nil,          -- 'retrying' | 'failed', read from Superwarp's own chat output (phase 8 only)
    sw_signal_at       = nil,          -- os.time() the signal was captured
    sw_last_sent_at    = nil,          -- os.time() the last sw_* command was issued
    seq_gen            = 0,            -- bumped on every phase change; invalidates stale action-queue callbacks
    seq_busy           = false,        -- phase 4/10: an action queue (run_action_queue) is currently in flight
    ack_wait_gen       = nil,          -- seq_gen value the current step is waiting on an ack for
    ack_resume         = nil,          -- function to call when that ack (or its timeout) arrives
}

-- prerender throttle
local nexttime = os.clock()
local delay    = 0

-- ==========================================================================
-- HUD
-- ==========================================================================
local hud = nil
if texts_success then
    hud = texts.new({
        pos    = {x = 10, y = 10},
        bg     = {alpha = 200, red = 0, green = 0, blue = 0},
        text   = {size = 10, font = 'Consolas',
                  stroke = {width = 1, alpha = 255, red = 0, green = 0, blue = 0}},
        flags  = {bold = true, draggable = true},
    })
    -- Hidden until //df start (avoid rendering at character select).
end

local function update_hud()
    if not hud then return end
    local status_text = state.running and '\\cs(100,255,100)[RUNNING]\\cr'
                                       or '\\cs(255,100,100)[PAUSED]\\cr'
    local target = rotation[state.zone_index]
    local lines = {
        '  DomainFarm ' .. status_text,
        '  Target: \\cs(100,200,255)' .. (target and target.label or 'None') .. '\\cr',
        '  Action: \\cs(255,255,100)' .. (PHASE_NAMES[state.phase] or 'Unknown') .. '\\cr',
    }
    if state.phase == 6 then
        local eng = state.target_name
            and ('\\cs(255,150,150)' .. state.target_name .. '\\cr')
            or  '\\cs(150,150,150)waiting for spawn\\cr'
        lines[#lines + 1] = '  Engaging: ' .. eng .. '  (kills: ' .. state.kills .. ')'
    end
    if state.hud_note then
        lines[#lines + 1] = '  \\cs(200,200,200)' .. state.hud_note .. '\\cr'
    end
    if state.fail_reason then
        lines[#lines + 1] = '  \\cs(255,80,80)' .. state.fail_reason .. '\\cr'
    end
    hud:text(table.concat(lines, '  \n') .. '  ')
end

-- ==========================================================================
-- SMALL HELPERS
-- ==========================================================================
local function stop_bot(reason)
    state.running  = false
    state.phase    = 0
    state.fighting = false
    state.hud_note = nil      -- never leave "Zone settling..." etc. on a stopped HUD
    state.settle_until = nil
    windower.ffxi.run(false)
    if reason then
        state.fail_reason = reason
        error(reason)   -- logger's error(): prints in red, does not raise
    end
    update_hud()
end

-- Central phase transition: resets everything a stale phase could poison.
-- `reason` is optional and only used for the transition log / //df status.
local function set_phase(p, reason)
    if state.phase ~= p then
        local from = state.phase
        state.last_transition = ('%s -> %s%s'):format(
            PHASE_NAMES[from] or tostring(from), PHASE_NAMES[p] or tostring(p),
            reason and (' (' .. reason .. ')') or '')
        if settings.log_phases then log('Phase: ' .. state.last_transition) end
        state.phase            = p
        state.phase_started_at = os.time()
        state.waypoint_index   = 1
        state.last_pos         = nil
        state.sw_attempts      = 0
        state.seq_gen          = state.seq_gen + 1   -- invalidate any in-flight action-queue callbacks
        state.seq_busy         = false
        state.ack_wait_gen     = nil
        state.ack_resume       = nil
        if p == 1 or p == 7 then
            state.ring_started_at = nil
            state.ring_equip_sent = false
        end
        if p == 2 or p == 3 or p == 9 then
            -- Fresh approach: forget any previously found NPC / progress mark.
            state.approach_npc       = nil
            state.approach_best_dist = nil
        end
        if p == 3 or p == 9 then
            -- Fresh interaction: any captured menu snapshot is stale, and the
            -- terrain-following walk stage (if this zone has one) needs to
            -- run again from the start.
            state.domain_menu     = nil
            state.confluence_menu = nil
            state.wp_path_done    = false
        end
        if p ~= 6 then
            state.arena_positioned = false
        end
    end
end

-- Call whenever a phase makes measurable progress (waypoint reached, distance
-- to an NPC shrinking, ...) so the watchdog only fires on REAL stalls.
local function mark_progress()
    state.phase_started_at = os.time()
end

local function get_zone_id()
    local info = windower.ffxi.get_info()
    if not info or not info.zone or info.zone == 0 then return nil end
    return info.zone
end

local function isBuffActive(id)
    local player = windower.ffxi.get_player()
    if not player or not player.buffs then return false end
    for _, v in pairs(player.buffs) do
        if v == id then return true end
    end
    return false
end

-- Debuffs that prevent acting at all (movement/JA/spells).
local INCAPACITATED = {[0]=true, [2]=true, [7]=true, [10]=true, [14]=true,
                       [15]=true, [17]=true, [19]=true, [28]=true}
-- Additional debuffs that block spellcasting specifically.
local SPELL_BLOCKED = {[6]=true, [16]=true, [29]=true}

local function can_act()
    local player = windower.ffxi.get_player()
    if not player or not player.buffs then return false end
    for _, v in pairs(player.buffs) do
        if INCAPACITATED[v] then return false end
    end
    return true
end

local function can_cast()
    local player = windower.ffxi.get_player()
    if not player or not player.buffs then return false end
    for _, v in pairs(player.buffs) do
        if INCAPACITATED[v] or SPELL_BLOCKED[v] then return false end
    end
    return true
end

-- Stuck detection: returns true if we have made no progress for too long.
local function movement_stuck(me)
    local now = os.time()
    if not state.last_pos then
        state.last_pos = {x = me.x, y = me.y, t = now}
        return false
    end
    local moved = math.sqrt((me.x - state.last_pos.x)^2 + (me.y - state.last_pos.y)^2)
    if moved > 1 then
        state.last_pos = {x = me.x, y = me.y, t = now}
        return false
    end
    return (now - state.last_pos.t) > settings.stuck_timeout
end

-- Movement: single choke point so the call convention lives in one place.
-- Coordinate-based: we always compute the direction ourselves from a
-- player->target vector and drive windower.ffxi.run() with it. We never rely
-- on the client's auto-run-to-target, so behaviour is independent of the
-- in-game TargetLock setting.
local function heading_of(dx, dy)
    -- Checked against several independent, working Windower movement/follow
    -- addons: they all compute this as -atan2(dy, dx), not the plain
    -- (positive) atan2(dy, dx) this used to be. The unnegated version is a
    -- mirror-flipped heading -- correct only when the target is due east or
    -- west, increasingly wrong elsewhere -- which lines up with "still
    -- attacking and facing away from the mob" far better than a pure
    -- timing issue would.
    return -math.atan2(dy, dx)
end

local function run_towards(dx, dy)
    if dx == 0 and dy == 0 then return end
    if settings.movement_mode == 'heading' then
        windower.ffxi.run(heading_of(dx, dy))
    else
        windower.ffxi.run(dx, dy)
    end
end

local function face_towards(dx, dy)
    if dx == 0 and dy == 0 then return end
    windower.ffxi.turn(heading_of(dx, dy))
end

local function stop_running()
    windower.ffxi.run(false)
end

-- Resolve the boss's *current* position by ID and physically move toward it.
-- Returns 'arrived' | 'moving' | 'lost' | 'stuck'.
local function chase_mob_by_id(mob_id, range)
    local mob = mob_id and windower.ffxi.get_mob_by_id(mob_id)
    local me  = windower.ffxi.get_mob_by_target('me')
    if not mob or not me or not mob.x or not me.x then return 'lost' end

    local dx, dy = mob.x - me.x, mob.y - me.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= range then
        stop_running()
        face_towards(dx, dy)     -- melee requires facing; TargetLock-off won't do it for us
        return 'arrived'
    end
    if movement_stuck(me) then
        stop_running()
        return 'stuck'
    end
    run_towards(dx, dy)
    return 'moving'
end

-- Turns to face `mob`, waits one full tick for that turn to actually land,
-- THEN fires the engage packet -- rather than firing it in the same tick as
-- the turn. windower.ffxi.turn() needs at least a moment to rotate the
-- character; engaging immediately after can catch the client still
-- mid-turn (reported: "not always facing the mob perfectly when engaging").
-- Returns true once it has actually sent the engage packet.
local function engage_when_facing_ready(mob)
    local me = windower.ffxi.get_mob_by_target('me')
    if not state.facing_settled then
        if me and mob then
            face_towards(mob.x - me.x, mob.y - me.y)
        end
        state.facing_settled = true
        delay = 0.3
        return false
    end
    state.facing_settled = false
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target']       = mob.id,
        ['Target Index'] = mob.index,
        ['Category']     = 2,          -- engage
    }))
    delay = 1
    return true
end

-- ==========================================================================
-- EQUIPMENT / RING HANDLING
-- ==========================================================================
local function getEquippedItemName(slot_name)
    local items = windower.ffxi.get_items()
    if not items then return nil end
    local equipment = items.equipment
    if not equipment then return nil end
    local slot_index = equipment[slot_name]
    local slot_bag   = equipment[slot_name .. '_bag']
    if not slot_index or slot_index == 0 then return nil end   -- empty slot
    local item = windower.ffxi.get_items(slot_bag or 0, slot_index)
    if not item or not item.id or item.id == 0 then return nil end
    local item_res = res.items[item.id]
    return item_res and item_res.en or nil
end

-- Search equippable bags for an item by English name; returns true if found.
local function item_in_inventory(name)
    local item_res = res.items:with('en', name)
    if not item_res then return false end
    -- 0 = inventory, 8/10/11/12 = Wardrobe/2/3/4 (Windower's own wiki lists
    -- these as the only bags item functions officially document), plus
    -- 13-16 = Wardrobe 5-8 on characters that have them unlocked. Iterate
    -- with ipairs() over the bag's own table -- every real Windower addon
    -- that scans a bag does it this way. The previous `for i = 1,
    -- (contents.max or 0) do` relied on a `.max` field that doesn't appear
    -- to actually exist on what get_items() returns, which is a much
    -- better explanation for "found in inventory, not found in wardrobe"
    -- than a genuinely missing bag ID would be -- whatever inconsistency
    -- let it work at all was likely bag-shape-dependent, not something
    -- worth relying on further.
    for _, bag in ipairs({0, 8, 10, 11, 12, 13, 14, 15, 16}) do
        local contents = windower.ffxi.get_items(bag)
        if contents then
            for _, it in ipairs(contents) do
                if it and it.id == item_res.id then return true end
            end
        end
    end
    return false
end

-- Search the teleport_rings list for the first ring present in inventory.
-- Returns the ring name or nil if none found.
local function find_teleport_ring()
    for _, name in ipairs(settings.teleport_rings) do
        if item_in_inventory(name) then return name end
    end
    return nil
end

-- Equip (if needed) then use an enchanted ring. Bounded by ring_timeout.
local function process_ring(ring_name)
    local now = os.time()
    if not state.ring_started_at then
        state.ring_started_at = now
        if not item_in_inventory(ring_name) then
            stop_bot(('Ring "%s" not found in inventory/wardrobes. Bot stopped.'):format(ring_name))
            return
        end
    end
    if now - state.ring_started_at > settings.ring_timeout then
        stop_bot(('Ring "%s" failed to fire within %ds (uncharged / equip blocked?). Bot stopped.')
                 :format(ring_name, settings.ring_timeout))
        return
    end

    local right = getEquippedItemName('right_ring')
    local left  = getEquippedItemName('left_ring')
    if right ~= ring_name and left ~= ring_name then
        windower.send_command('input /equip ring2 "' .. ring_name .. '"')
        state.ring_equip_sent = true
        delay = 6          -- cover the enchant equip-delay before first use
    else
        windower.send_command('input /item "' .. ring_name .. '" <me>')
        delay = 15         -- item cast + activation window; retried until zone change
    end
end

-- ==========================================================================
-- TRUSTS (data + lookup live in libs/df_trusts.lua)
-- ==========================================================================
local function try_summon_trust()
    local next_trust = get_missing_trust()
    if next_trust and can_cast() then
        windower.send_command('input /ma "' .. next_trust .. '" <me>')
        delay = 6
        return true
    end
    return false
end

-- ==========================================================================
-- TARGET ACQUISITION (zone boss + bonus targets such as Mireu)
-- ==========================================================================
local function is_live_di_mob(mob)
    return mob ~= nil
        and mob.valid_target
        and mob.spawn_type == 16            -- monsters only
        and mob.hpp ~= nil and mob.hpp > 0
end

-- Distance from a mob to the arena anchor for the current rotation entry.
-- Returns math.huge when we can't compute it (missing coords) so such mobs
-- are never preferred but also never crash the scan.
local function arena_distance(mob, entry)
    local a = entry and entry.arena
    if not a or not mob or not mob.x or not mob.y then return math.huge end
    local dx, dy = mob.x - a.x, mob.y - a.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Find the Domain Invasion target we should be fighting right now.
--   * Sticky: if our cached target is still alive we keep it, rather than
--     re-scanning every tick. Mireu spawns in place of the zone's dragon,
--     not alongside it, so this is just cheap consistency, not conflict
--     resolution between two simultaneous targets.
--   * Otherwise scan the mob array for any live mob whose name is in the
--     zone's target set. Names are unique DI bosses, so no radius filter is
--     applied (the dragons roam far across the arena).
--   * Prefer a mob already claimed by us, then the closest to the arena anchor.
-- Announces the first sighting of an alternate spawn (Mireu) once per visit.
local function find_di_target()
    local entry = rotation[state.zone_index]
    if not entry or not entry.targets then return nil end

    -- Sticky fast path.
    if state.boss_id then
        local mob = windower.ffxi.get_mob_by_id(state.boss_id)
        if is_live_di_mob(mob) then return mob end
        -- target gone: fall through to a rescan
    end

    local mob_array = windower.ffxi.get_mob_array()
    if not mob_array then return nil end

    local me = windower.ffxi.get_mob_by_target('me')
    local my_id = me and me.id or nil

    local best, best_score = nil, math.huge
    for _, mob in pairs(mob_array) do
        if mob and mob.name and entry.targets[mob.name] and is_live_di_mob(mob) then
            -- Claimed-by-us wins outright; otherwise closest to the arena.
            local score = arena_distance(mob, entry)
            if my_id and mob.claim_id == my_id then score = -1 end
            if score < best_score then
                best, best_score = mob, score
            end
        end
    end

    if best then
        state.boss_id = best.id
        state.target_name = best.name
        if best.name ~= entry.boss and not state.bonus_seen[best.name] then
            state.bonus_seen[best.name] = true
            log(('%s spawned in place of %s this visit. Engaging.'):format(best.name, entry.boss))
        end
    end
    return best
end

-- Backwards-compatible alias used by older call sites / tests.
local get_boss = find_di_target

local function reset_arena_tracking()
    state.boss_id            = nil
    state.boss_missing_since = nil
    state.target_name        = nil
    state.pending_advance    = false
    state.kills              = 0
    state.bonus_seen         = {}
    state.facing_settled     = false
end

-- ==========================================================================
-- ARENA APPROACH PATH (post-teleport short walk to the boss engagement spot)
-- ==========================================================================
-- Walks an ordered list of {x, y} waypoints, advancing state.waypoint_index
-- as each is reached within settings.waypoint_range. Returns true once the
-- whole list is exhausted. Used for the post-teleport arena walk (phase 6)
-- and, since v11.1, the terrain-following walk to the Domain NPC / Confluence
-- (phases 3/9) before the dynamic find-and-interact takes over for the last
-- stretch. `label` is only used for the stuck-log message.
local function executeArenaPath(wps, label)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return false end

    local wp = wps[state.waypoint_index]
    if not wp then
        stop_running()
        return true
    end

    local dist = math.sqrt((wp.x - me.x)^2 + (wp.y - me.y)^2)
    if dist > settings.waypoint_range then
        if movement_stuck(me) then
            stop_running()
            log(('Stuck approaching %s; holding position.'):format(label or 'the arena engagement spot'))
            return false
        end
        run_towards(wp.x - me.x, wp.y - me.y)
        delay = 0.1
        return false
    else
        state.waypoint_index = state.waypoint_index + 1
        state.last_pos = nil
        mark_progress()
        return false
    end
end

-- ==========================================================================
-- NPC APPROACH (Dimensional Portal / Domain Invasion NPC / Undulating
-- Confluence) -- one shared, dynamic implementation for all three
-- ==========================================================================
local function find_first_mob_by_name(names)
    for _, name in ipairs(names) do
        local mob = windower.ffxi.get_mob_by_name(name)
        if mob then return mob end
    end
    return nil
end

-- Walk to and interact with the nearest live NPC matching any of `names`,
-- caching the found entity under state.approach_npc so the shared
-- 'incoming chunk' handler (below) knows which NPC's menu response to
-- expect. See this file's header comment for why phases 3 and 9 use this
-- dynamic approach instead of the fixed waypoints they used to.
local function approach_and_interact(names)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return end

    -- Always work from a FRESH snapshot. mob.distance is computed at fetch
    -- time and does not update on a cached table -- even though these NPCs
    -- are stationary, a stale snapshot's .distance stays frozen at whatever
    -- it was when first spotted, so the arrival check below would never see
    -- us as "close enough" no matter how close we actually walked (this was
    -- the "walks right up and wiggles" bug: a correct live heading, checked
    -- against a dead distance reading). Once we know the NPC's ID, re-fetch
    -- it by ID each tick (cheap) instead of re-scanning the whole mob list
    -- by name (find_first_mob_by_name) every time.
    local npc = state.approach_npc and windower.ffxi.get_mob_by_id(state.approach_npc.id)
    if not npc then
        npc = find_first_mob_by_name(names)
    end
    state.approach_npc = npc
    if not npc then
        -- Not in tracking range yet; keep checking rather than spinning fast.
        delay = 2
        return
    end

    local dist = math.sqrt(npc.distance or 0)
    if dist > settings.npc_range then
        if movement_stuck(me) then
            stop_running()
            stop_bot(('Stuck while approaching %s. Bot stopped.'):format(npc.name))
            return
        end
        -- Closing in on the NPC counts as progress for the watchdog.
        if not state.approach_best_dist or dist < state.approach_best_dist - 1 then
            state.approach_best_dist = dist
            mark_progress()
        end
        run_towards(npc.x - me.x, npc.y - me.y)
        delay = 0.1
    else
        stop_running()
        packets.inject(packets.new('outgoing', 0x01A, {
            ['Target']       = npc.id,
            ['Target Index'] = npc.index,
            ['Category']     = 0,          -- NPC interaction
        }))
        delay = 5
    end
end

-- How long to wait for a menu's own 0x05C acknowledgement before giving up
-- on it and continuing anyway (keeps a missing/renamed ack from hanging the
-- bot forever; see run_action_queue).
local ACK_TIMEOUT = 5

-- Fires a pre-built ordered list of {packet, wait_ack, delay} steps (see
-- libs/df_eschawarp.lua). Steps with wait_ack=true wait for a real incoming
-- 0x05C -- the menu's own acknowledgement of the previous selection -- before
-- the next one fires, rather than a guessed fixed delay; `delay` is unused
-- for those. Steps with wait_ack=false just wait `delay` seconds. This is
-- what fixed the "interacting with Affi never warped to the arena" bug:
-- map/escha.lua's domain sequence waits on this ack for nearly every step,
-- and firing the next menu selection before the server had processed the
-- last one silently derailed the sequence.
-- Guards against stale callbacks from an abandoned sequence (e.g. a
-- watchdog recovery mid-sequence) via state.seq_gen, which set_phase()
-- bumps on every transition.
local function run_action_queue(steps, on_done)
    local my_gen = state.seq_gen
    local i = 0
    local function next_step()
        if state.seq_gen ~= my_gen then return end   -- superseded; abandon
        i = i + 1
        local step = steps[i]
        if not step then
            if on_done then on_done() end
            return
        end
        packets.inject(step.packet)
        if step.wait_ack then
            state.ack_wait_gen = my_gen
            state.ack_resume   = next_step
            coroutine.schedule(function()
                if state.seq_gen == my_gen and state.ack_wait_gen == my_gen then
                    warning(('Menu sequence: no ack for step %d within %ds; continuing anyway.'):format(i, ACK_TIMEOUT))
                    state.ack_wait_gen = nil
                    state.ack_resume   = nil
                    next_step()
                end
            end, ACK_TIMEOUT)
        else
            coroutine.schedule(next_step, step.delay or 0)
        end
    end
    state.seq_busy = true
    next_step()
end

-- ==========================================================================
-- ZONE REALITY ROUTER (ID-based)
-- ==========================================================================
-- Which DI zone does the current rotation target live in?
local function target_zone_id()
    local t = rotation[state.zone_index]
    return t and t.zone or nil
end

-- Phase to use when standing INSIDE the target DI zone.
local function in_target_zone_phase()
    if isBuffActive(settings.elvorseal_buff) then return 6 end
    return 3   -- approach the Domain Invasion NPC; uniform for all 3 zones (v11)
end

-- Phase to use when standing in a town / safe zone.
local function travel_phase_from_town()
    return state.zone_index == 1 and 1 or 8
end

-- Phase to use when we're somewhere unexpected and need to leave. The Dim.
-- Ring (phase 1) has no zone gate -- it works from anywhere -- so when the
-- target is Reisenjima there's no reason to detour home through the Warp
-- Ring first just to turn around and use the Dim. Ring from there instead.
-- Superwarp's Home Point menu (phase 8, for Zi'Tah/Ru'Aun) has no such
-- shortcut; it only works from a proper town, so a Warp Ring trip home
-- really is required for those two targets. This is exactly what "//df
-- start" from a conflux zone (e.g. Qufim) while targeting Reisenjima used
-- to trip on: Qufim matched no positive branch (it's only ever "expected"
-- when the target is Zi'Tah/Ru'Aun), so it fell through to a blind warp
-- home even though the ring it needed works from right where it was.
local function escape_phase()
    return state.zone_index == 1 and 1 or 7
end

-- Conflux zone that leads to the current target (nil for Reisenjima).
local function expected_conflux_zone()
    if state.zone_index == 2 then return ZONES.qufim end
    if state.zone_index == 3 then return ZONES.misareaux end
    return nil
end

-- Pick the phase that can make progress from the zone we are physically in.
-- Used by //df start, //df resume and the watchdog's soft recovery.
local function reroute_from_reality(zone_id, reason)
    stop_running()
    if not zone_id then
        warning('Zone unknown at "' .. reason .. '" (client still loading/zoning?); warping home to recover.')
        set_phase(7, reason .. '; zone unknown, warping home')
    elseif safe_zone_ids[zone_id] then
        set_phase(travel_phase_from_town(), reason)
    elseif zone_id == target_zone_id() then
        state.fighting = false
        set_phase(in_target_zone_phase(), reason)
    elseif conflux_zone_ids[zone_id] and zone_id == expected_conflux_zone() then
        set_phase(9, reason)
    elseif portal_zone_ids[zone_id] and state.zone_index == 1 then
        set_phase(2, reason)
    else
        warning(('"%s" is not in safe_zone_names / any known target/conflux/crag zone at "%s". Add it to libs/df_zones.lua if it is a valid start/home point.')
                :format(zone_name_of(zone_id), reason))
        set_phase(escape_phase(), reason .. '; leaving')
    end
end

-- Every zone-vs-phase combination the bot can find itself in is resolved
-- here, every tick. The rule of thumb: if the current phase cannot make
-- progress in the current zone for the current target, pick one that can.
-- Phase 7 (Warp Ring home) is the universal escape hatch from any field zone.
local function enforce_zone_reality(zone_id)
    -- Dead-recovery (phase 11) may only be rerouted once we reach a safe zone;
    -- no other branch is allowed to yank the bot out of it.
    if state.phase == 11 and not safe_zone_ids[zone_id] then return end

    if safe_zone_ids[zone_id] then
        state.unknown_zone_since = nil
        if state.phase == 11 then
            -- Arrived at home point after death: restart travel.
            state.death_latched = false
            state.fighting = false
            set_phase(travel_phase_from_town(), 'back in town after death')
        elseif state.phase > 1 and state.phase < 7 then
            state.fighting = false
            set_phase(travel_phase_from_town(), 'in a safe zone with a field phase active')
        elseif state.phase == 7 then
            set_phase(travel_phase_from_town(), 'warp home complete')
        elseif state.phase == 1 and state.zone_index ~= 1 then
            set_phase(8, 'target is not Reisenjima; use Superwarp, not the Dim. Ring')
        elseif state.phase == 8 and state.zone_index == 1 then
            set_phase(1, 'target is Reisenjima; use the Dim. Ring, not Superwarp')
        elseif state.phase == 9 or state.phase == 10 then
            set_phase(travel_phase_from_town(), 'conflux phase while still in town')
        end
        return
    end

    -- Outside town: never interrupt an in-progress warp home.
    if state.phase == 7 then return end

    if conflux_zone_ids[zone_id] then
        state.unknown_zone_since = nil
        if zone_id ~= expected_conflux_zone() then
            stop_running()
            set_phase(escape_phase(), ('in %s but the target is %s; leaving'):format(zone_name_of(zone_id), rotation[state.zone_index].label))
        elseif state.phase ~= 9 and state.phase ~= 10 then
            set_phase(9, 'arrived in conflux zone')
        end

    elseif portal_zone_ids[zone_id] then
        state.unknown_zone_since = nil
        if state.zone_index ~= 1 then
            stop_running()
            set_phase(escape_phase(), ('at a crag but the target is %s; leaving'):format(rotation[state.zone_index].label))
        elseif state.phase ~= 2 then
            set_phase(2, 'arrived at crag')
        end

    elseif zone_id == ZONES.reisenjima or zone_id == ZONES.zitah or zone_id == ZONES.ruaun then
        state.unknown_zone_since = nil
        if zone_id ~= target_zone_id() then
            -- Standing in a DI zone that is not the current target (e.g. started
            -- with the wrong argument, or a stale rotation index). Leave.
            stop_running()
            set_phase(escape_phase(), ('in %s but the target is %s; leaving'):format(zone_name_of(zone_id), rotation[state.zone_index].label))
        else
            -- Valid arena phases: 3/4/5/6, uniform for all three zones (v11).
            if state.phase < 3 or state.phase > 6 then
                stop_running()
                set_phase(in_target_zone_phase(), 'arrived in target zone')
            end
        end

    else
        local now = os.time()
        if state.last_unhandled_zone ~= zone_id then
            warning(('Unrecognized zone "%s" at phase %d. Add it to safe_zone_names if it is a valid start/home point.')
                    :format(zone_name_of(zone_id), state.phase))
            state.last_unhandled_zone = zone_id
        end
        if not state.unknown_zone_since then state.unknown_zone_since = now end
        -- After a grace period, use the Warp Ring to get somewhere we understand.
        if settings.unknown_zone_grace > 0 and state.unknown_zone_since
           and now - state.unknown_zone_since > settings.unknown_zone_grace then
            state.unknown_zone_since = nil
            stop_running()
            set_phase(escape_phase(), 'unrecognized zone for ' .. settings.unknown_zone_grace .. 's; leaving')
        end
    end
end

-- ==========================================================================
-- PHASE HANDLERS
-- ==========================================================================
-- Phase 4: the Domain NPC's menu was captured in phase 3 (state.domain_menu).
-- Decide whether the dragon is up; if so, request Elvorseal (if needed) and
-- warp to the arena; if not, cancel and retry later. See libs/df_eschawarp.lua.
local function phase_4_domain_menu()
    if state.seq_busy then return end   -- domain sequence already in flight; wait for its own callbacks
    local menu = state.domain_menu
    if not menu then
        -- No snapshot (e.g. a soft-recovery landed us here directly): go
        -- re-interact rather than guess.
        set_phase(3, 'no domain menu captured; retrying interaction')
        return
    end
    state.domain_menu = nil

    local dragon_state, has_elvorseal = eschawarp.read_domain_status(menu.menu_params)
    if eschawarp.domain_not_ready(dragon_state) then
        packets.inject(eschawarp.build_domain_cancel(menu))
        state.elvorseal_fails = state.elvorseal_fails + 1
        if state.elvorseal_fails >= settings.elvorseal_max then
            stop_bot(('Domain Invasion not active after %d checks (event inactive / daily cap?). Bot stopped.')
                     :format(state.elvorseal_fails))
            return
        end
        log(('Domain Invasion not active yet (check %d/%d). Retrying in %ds.')
            :format(state.elvorseal_fails, settings.elvorseal_max, settings.elvorseal_retry))
        set_phase(3, 'dragon not ready; retry')
        delay = settings.elvorseal_retry
        return
    end

    state.elvorseal_fails = 0
    local seq = eschawarp.build_domain_sequence(menu, has_elvorseal)
    if not seq then
        stop_bot(('No known arena landing spot for zone %d. Bot stopped.'):format(menu.zone))
        return
    end
    log(has_elvorseal and 'Warping to battle...' or 'Getting Elvorseal, then warping to battle...')
    run_action_queue(seq, function()
        state.seq_busy = false
        state.elvorseal_sent_at = os.time()
        nexttime = os.clock()   -- wake the main loop immediately; total time varied (ack-driven)
        delay = 0
        set_phase(5, 'Elvorseal sequence sent')
    end)
    delay = 2   -- re-checked periodically while seq_busy guards against re-entry
end

local function phase_5_verify_elvorseal()
    if isBuffActive(settings.elvorseal_buff) then
        state.elvorseal_fails = 0
        set_phase(6, 'Elvorseal active')
        return
    end
    if state.elvorseal_sent_at and os.time() - state.elvorseal_sent_at > 10 then
        state.elvorseal_fails = state.elvorseal_fails + 1
        if state.elvorseal_fails >= settings.elvorseal_max then
            stop_bot(('Elvorseal failed %d times (event inactive / daily cap / packet sequence out of date?). Bot stopped.')
                     :format(state.elvorseal_fails))
            return
        end
        log(('Elvorseal not detected (attempt %d/%d). Retrying in %ds.')
            :format(state.elvorseal_fails, settings.elvorseal_max, settings.elvorseal_retry))
        delay = settings.elvorseal_retry
        set_phase(4, 'Elvorseal not detected; retry')
    end
end

local function advance_rotation()
    state.watchdog_recoveries = 0   -- fresh soft-recovery budget for the next leg
    if state.zone_index == 1 then
        state.zone_index = 2
        set_phase(7, 'rotation -> Zi\'Tah; warping home first')
    elseif state.zone_index == 2 then
        state.zone_index = 3
        set_phase(7, 'rotation -> Ru\'Aun; warping home first')
    else
        state.zone_index = 1
        state.selected_tp_ring = nil   -- re-scan rings next cycle (charges may have changed)
        set_phase(1, 'rotation -> Reisenjima')
    end
    reset_arena_tracking()
end

local function handle_death(player)
    state.fighting = false
    stop_running()
    if not state.death_latched then
        state.death_latched = true
        set_phase(11, 'player died; returning to Home Point')
        delay = 8
    end
end

local function phase_11_dead(player)
    if player.status ~= 2 and player.status ~= 3 then
        -- Raised or already back up: hand control back to the router.
        state.death_latched = false
        set_phase(state.zone_index == 1 and 1 or 8, 'no longer dead')
        return
    end
    -- Reraise dialogue: Param 0 selects "return to Home Point".
    local p = packets.new('outgoing', 0x01A, {
        ['Target']       = player.id,
        ['Target Index'] = player.index,
        ['Category']     = 0x0D,
        ['Param']        = 0,
    })
    packets.inject(p)
    delay = 10   -- re-sent on a slow cadence until the zone change fires
end

local function phase_6_combat(player)
    local target = rotation[state.zone_index]
    local boss = get_boss()
    local now = os.time()

    -- Death check: strictly status 2/3 (never cutscene status 4 etc).
    if player.status == 2 or player.status == 3 then
        handle_death(player)
        return
    end

    -- Target liveness bookkeeping with a despawn grace period, so a target that
    -- merely left tracking range isn't declared dead.
    if boss then
        state.fighting = true
        state.boss_missing_since = nil
        -- A visible, living target is progress: keep the combat watchdog fresh so
        -- a long fight is never mistaken for a stall.
        state.phase_started_at = now
    elseif state.fighting then
        if not state.boss_missing_since then
            state.boss_missing_since = now
            return
        elseif now - state.boss_missing_since < 6 then
            return
        end
        -- Confirmed gone. Mireu spawns in place of the zone's dragon, not
        -- alongside or after it -- exactly one of them is ever up in a given
        -- visit, and killing whichever one it was clears the arena. No
        -- reason to linger scanning for a second target that was never
        -- coming.
        state.fighting = false
        state.boss_missing_since = nil
        state.kills = state.kills + 1
        stop_running()
        log(('%s defeated or despawned. Arena clear.'):format(state.target_name or target.boss))
        state.boss_id = nil
        state.target_name = nil
        state.pending_advance = true
        if player.status == 1 then
            -- Disengage so we can re-engage a new target (or use a ring later).
            windower.send_command('input /attack off')
            delay = 3
        end
        return
    elseif state.pending_advance then
        -- Disengage completed (or wasn't needed); move on.
        if player.status == 1 then
            windower.send_command('input /attack off')
            delay = 3
            return
        end
        state.pending_advance = false
        advance_rotation()
        return
    end

    -- Elvorseal wore off / rejected mid-phase.
    if not isBuffActive(settings.elvorseal_buff) then
        state.fighting = false
        set_phase(4)
        return
    end

    -- Not yet fighting: take up position and summon trusts.
    if not state.fighting and player.status == 0 then
        local me = windower.ffxi.get_mob_by_target('me')
        if not me then return end
        if state.zone_index == 1
           and (math.abs(reisen_arena.x - me.x) > 2 or math.abs(reisen_arena.y - me.y) > 2) then
            if movement_stuck(me) then
                stop_running()
                log('Stuck approaching the Reisenjima arena spot; holding position.')
            else
                run_towards(reisen_arena.x - me.x, reisen_arena.y - me.y)
            end
        elseif state.zone_index == 2 and not state.arena_positioned then
            state.arena_positioned = executeArenaPath(zitah_arena_wps, 'the arena engagement spot')
        elseif state.zone_index == 3 and not state.arena_positioned then
            state.arena_positioned = executeArenaPath(ruaun_arena_wps, 'the arena engagement spot')
        else
            stop_running()
            try_summon_trust()
        end
        return
    end

    -- Engage / chase / hold.
    -- Chasing is coordinate-based (chase_mob_by_id): we re-read the boss's
    -- position by ID every tick and steer toward it ourselves, so the client's
    -- auto-run-to-target (and therefore the TargetLock setting) is irrelevant.
    if boss and player.status == 0 and state.fighting then
        local result = chase_mob_by_id(boss.id, settings.engage_range)
        if result == 'arrived' then
            engage_when_facing_ready(boss)
        elseif result == 'stuck' then
            if not state.facing_settled then
                log('Stuck while closing on ' .. (boss.name or target.boss) .. '; engaging from here.')
                state.last_pos = nil
            end
            engage_when_facing_ready(boss)
        else
            state.facing_settled = false
            delay = 0.2
        end
    elseif boss and player.status == 1 and state.fighting then
        local result = chase_mob_by_id(boss.id, settings.engage_range)
        if result == 'moving' then
            delay = 0.2
        elseif result == 'stuck' then
            log('Chase stuck on geometry; pausing movement briefly.')
            state.last_pos = nil
            delay = 2
        else
            -- 'arrived' (stopped and facing the boss) or 'lost' (rescan next tick)
            try_summon_trust()
        end
    end
end

local function phase_8_superwarp(zone_id)
    -- Defensive: enforce_zone_reality() should never leave the router here
    -- while the target is Reisenjima, but if a future edit to the router
    -- ever reopens that path, self-correct instead of silently spamming the
    -- wrong Superwarp command forever.
    if state.zone_index == 1 then
        set_phase(1, 'phase 8 guard: target is Reisenjima, use the Dim. Ring, not Superwarp')
        return
    end
    if not safe_zone_ids[zone_id] then return end

    if state.sw_signal == 'retrying' then
        -- Superwarp is already re-issuing this call on its own; don't stack
        -- a second command on top of its retry loop, just wait it out a
        -- little longer and re-check.
        state.sw_signal = nil
        mark_progress()
        delay = 3
        return
    end
    -- A 'failed' signal means Superwarp already gave up on this attempt, so
    -- fall through and resend now instead of waiting out the rest of the
    -- delay. No signal at all (unrecognized message / different Superwarp
    -- version) falls through too, on the original fixed 15s cadence -- this
    -- degrades gracefully to the old timer-only behavior.
    state.sw_signal = nil

    state.sw_attempts = state.sw_attempts + 1
    if state.sw_attempts > 6 then
        stop_bot('Superwarp HP warp is not zoning us (is Superwarp loaded / HP unlocked?). Bot stopped.')
        return
    end
    if state.zone_index == 2 then
        windower.send_command(settings.sw_qufim)
    elseif state.zone_index == 3 then
        windower.send_command(settings.sw_misareaux)
    end
    state.sw_last_sent_at = os.time()
    delay = 15
end

-- Two-stage NPC approach: walk a known terrain-following waypoint path (if
-- one exists for the current zone) first, THEN switch to the dynamic
-- find-and-interact for the last stretch. A straight-line vector walk alone
-- (approach_and_interact on its own) can't route around a wall or ledge
-- between the zone entrance and the NPC -- that's what the fixed path is
-- for. The dynamic step on top of it is still worth keeping even with the
-- path restored: it's what fixed the original "too far / no eschan npcs
-- found" crash, since a hardcoded path alone only ever gets you *close*,
-- not guaranteed within interact range or correctly facing/targeting a
-- specific live entity.
local function approach_via_waypoints_then_interact(wps, names, label)
    if wps and not state.wp_path_done then
        if executeArenaPath(wps, label) then
            state.wp_path_done = true
            state.last_pos = nil
        end
        return
    end
    approach_and_interact(names)
end

-- Phase 9: approach the Undulating Confluence. Phase 10: the confluence's
-- menu was captured in phase 9 (state.confluence_menu); fire the "enter"
-- sequence. See libs/df_eschawarp.lua.
local function phase_9_approach_confluence()
    if state.zone_index == 1 then
        -- Defensive: Reisenjima never routes through the conflux; if this
        -- ever fires anyway, self-correct with the Dim. Ring (works from
        -- anywhere) instead of detouring home first.
        set_phase(escape_phase(), 'phase 9 guard: Reisenjima has no conflux step')
        return
    end
    local wps = (state.zone_index == 2 and q_waypoints) or (state.zone_index == 3 and m_waypoints) or nil
    approach_via_waypoints_then_interact(wps, eschawarp.CONFLUENCE_NPC_NAMES, 'the Undulating Confluence')
end

local function phase_10_enter_escha_menu()
    if state.zone_index == 1 then
        set_phase(escape_phase(), 'phase 10 guard: Reisenjima has no conflux step')
        return
    end
    if state.seq_busy then return end   -- enter sequence already in flight
    local menu = state.confluence_menu
    if not menu then
        set_phase(9, 'no confluence menu captured; retrying interaction')
        return
    end
    state.confluence_menu = nil

    log('Entering Escha...')
    local seq = eschawarp.build_enter_sequence(menu)
    run_action_queue(seq, function()
        state.seq_busy = false
        -- No explicit set_phase here: the reality router picks up the real
        -- zone change on its own once it happens.
    end)
    delay = 2
end

-- ==========================================================================
-- WATCHDOG SOFT RECOVERY
-- ==========================================================================
-- Re-derive the phase from physical reality instead of trusting the stalled
-- one. Town -> restart travel; target zone -> re-request/re-path; anywhere
-- else -> Warp Ring home. If that yields the same phase (e.g. a legitimately
-- long boss wait) we simply reset the path and give it another full window.
local function watchdog_recover(zone_id)
    local before = state.phase
    stop_running()
    state.waypoint_index    = 1
    state.last_pos          = nil
    state.approach_npc       = nil
    state.approach_best_dist = nil
    state.domain_menu        = nil
    state.confluence_menu    = nil
    state.wp_path_done       = false
    state.sw_attempts       = 0
    state.elvorseal_sent_at = nil

    if state.phase == 11 then
        -- Still dead / waiting on the home-point menu: just re-send.
        state.death_latched = false
    else
        reroute_from_reality(zone_id, 'watchdog recovery')
    end

    if state.phase == before then
        -- Same phase re-selected: retry it from scratch with a fresh window.
        state.phase_started_at = os.time()
        log(('Watchdog: retrying "%s" from scratch.'):format(PHASE_NAMES[state.phase] or state.phase))
    end
    delay = 2
end

-- ==========================================================================
-- ZONE CONFIRMATION GATE
-- ==========================================================================
-- Returns the set of zone IDs in which the given phase is allowed to touch
-- NPCs/mobs, or nil for phases that need no gate (ring use, idle).
local function expected_zones_for_phase(phase)
    local target = rotation[state.zone_index]
    if phase == 2 then
        return portal_zone_ids
    elseif phase >= 3 and phase <= 6 then
        -- Domain NPC approach, Elvorseal and combat: only in THE target zone.
        if target and target.zone then return {[target.zone] = true} end
        return {}
    elseif phase == 8 then
        return safe_zone_ids
    elseif phase == 9 or phase == 10 then
        if state.zone_index == 2 and ZONES.qufim then return {[ZONES.qufim] = true} end
        if state.zone_index == 3 and ZONES.misareaux then return {[ZONES.misareaux] = true} end
        return conflux_zone_ids
    end
    return nil
end

-- True when the current zone is acceptable for the current phase.
local function zone_gate_open(zone_id)
    local allowed = expected_zones_for_phase(state.phase)
    if allowed == nil then return true end
    return allowed[zone_id] == true
end

-- Post-zone settling: entities are unreliable for a few seconds after a zone
-- line. Any time the observed zone ID changes we arm a settle window.
local function zone_settling(zone_id)
    local now = os.time()
    if state.last_seen_zone ~= zone_id then
        state.last_seen_zone = zone_id
        state.settle_until   = now + settings.zone_settle
    end
    return state.settle_until ~= nil and now < state.settle_until
end

-- ==========================================================================
-- MAIN LOOP
-- ==========================================================================
windower.register_event('prerender', function()
    update_hud()

    local curtime = os.clock()
    if not state.running or nexttime + delay > curtime then return end
    nexttime = curtime
    delay = 0.2

    local zone_id = get_zone_id()
    if not zone_id or not res.zones[zone_id] then return end   -- zoning / transition
    local player = windower.ffxi.get_player()
    if not player then return end

    -- A leg that hops through several zones (town -> conflux -> Escha) used
    -- to share one watchdog_recoveries budget across every hop. Refresh it
    -- on every actual zone change instead, so a couple of small unrelated
    -- hiccups a leg apart don't add up to a hard stop.
    if state.last_recovery_zone ~= zone_id then
        if state.last_recovery_zone ~= nil and state.watchdog_recoveries > 0 then
            log(('Watchdog: recovery budget refreshed (0/%d) after reaching %s.')
                :format(settings.watchdog_recoveries, zone_name_of(zone_id)))
        end
        state.last_recovery_zone  = zone_id
        state.watchdog_recoveries = 0
    end

    -- Global death check (any phase).
    if (player.status == 2 or player.status == 3) and state.phase ~= 11 then
        handle_death(player)
        return
    end

    enforce_zone_reality(zone_id)

    -- Phase-specific watchdog. Soft-recover (re-derive the phase from where we
    -- actually are) a bounded number of times before giving up.
    local timeout = PHASE_TIMEOUTS[state.phase]
    if timeout and state.phase > 0 and os.time() - state.phase_started_at > timeout then
        local pname = PHASE_NAMES[state.phase] or tostring(state.phase)
        if state.watchdog_recoveries < settings.watchdog_recoveries then
            state.watchdog_recoveries = state.watchdog_recoveries + 1
            warning(('Watchdog: phase "%s" exceeded %ds without progress. Soft recovery %d/%d.')
                    :format(pname, timeout, state.watchdog_recoveries, settings.watchdog_recoveries))
            watchdog_recover(zone_id)
            return
        end
        stop_bot(('Watchdog: phase "%s" exceeded %ds without progress (%d recoveries failed). Bot stopped. Use //df resume to retry.')
                 :format(pname, timeout, state.watchdog_recoveries))
        return
    end

    -- Post-zone settling: hold off all entity interaction for a few seconds
    -- after the observed zone ID changes.
    if zone_settling(zone_id) then
        state.hud_note = 'Zone settling...'
        stop_running()
        delay = 0.5
        return
    end

    -- Zone confirmation gate: phases that touch NPCs/mobs only execute when
    -- we are physically in the zone they expect (e.g. never look for the
    -- Domain Invasion NPC while still standing in Qufim).
    if not zone_gate_open(zone_id) then
        state.hud_note = 'Waiting for zone: ' .. zone_name_of(zone_id) .. ' is not the expected zone'
        stop_running()
        delay = 1
        return
    end
    state.hud_note = nil

    local p = state.phase
    if     p == 1  then
        -- Pick the first available Dim. Ring on this cycle (cached in state).
        if not state.selected_tp_ring then
            state.selected_tp_ring = find_teleport_ring()
            if not state.selected_tp_ring then
                stop_bot('No Dimensional Ring found in inventory (checked: '
                         .. table.concat(settings.teleport_rings, ', ') .. '). Bot stopped.')
                return
            end
            log('Using ' .. state.selected_tp_ring .. ' for this cycle.')
        end
        process_ring(state.selected_tp_ring)
    elseif p == 2  then approach_and_interact({'Dimensional Portal'})
    elseif p == 3  then
        local wps = (state.zone_index == 2 and zitah_waypoints) or (state.zone_index == 3 and ruaun_waypoints) or nil
        approach_via_waypoints_then_interact(wps, eschawarp.DOMAIN_NPC_NAMES, 'the Domain Invasion NPC')
    elseif p == 4  then phase_4_domain_menu()
    elseif p == 5  then phase_5_verify_elvorseal()
    elseif p == 6  then phase_6_combat(player)
    elseif p == 7  then
        if player.status == 1 then
            windower.send_command('input /attack off')
            delay = 3
        else
            process_ring(settings.warp_ring)
        end
    elseif p == 8  then phase_8_superwarp(zone_id)
    elseif p == 9  then phase_9_approach_confluence()
    elseif p == 10 then phase_10_enter_escha_menu()
    elseif p == 11 then phase_11_dead(player)
    end
end)

-- ==========================================================================
-- EVENTS
-- ==========================================================================
windower.register_event('zone change', function(new_id, old_id)
    nexttime = os.clock()
    delay = 8
    -- Clear anything that must not survive a zone line.
    state.approach_npc       = nil
    state.approach_best_dist = nil
    state.domain_menu        = nil
    state.confluence_menu    = nil
    state.wp_path_done       = false
    state.seq_gen            = state.seq_gen + 1
    state.seq_busy           = false
    state.ack_wait_gen       = nil
    state.ack_resume         = nil
    reset_arena_tracking()
    state.waypoint_index  = 1
    state.last_pos        = nil
    state.sw_attempts     = 0
    state.fighting        = false
    state.arena_positioned = false
    state.phase_started_at = os.time()   -- fresh watchdog window in the new zone
    -- Arm the post-zone settle window explicitly (zone_settling() also re-arms
    -- it when the observed zone ID changes on the next tick).
    state.last_seen_zone  = nil
    state.settle_until    = os.time() + settings.zone_settle
    state.hud_note        = 'Zone settling...'
    stop_running()
end)

windower.register_event('logout', function()
    if state.running then
        state.running = false
        state.phase   = 0
        log('Logged out: DomainFarm paused. Use //df start after logging back in.')
    end
end)

-- Read Superwarp's OWN chat output instead of only trusting a fixed timer,
-- for phase 8 (the only phase left that drives a Superwarp command). Read
-- this file's header + libs/df_eschawarp.lua's header for why phases 4/10
-- no longer need this. Superwarp logs its NPC-lookup failures as
-- "No <x> found!" (terminal) or "No <x> found! Retrying..." (it is already
-- handling the problem itself). We deliberately match on that one shared
-- substring rather than hardcoding every message Superwarp can print
-- (version-specific and not something we vendor), so this degrades
-- gracefully -- if Superwarp's phrasing doesn't match, sw_signal simply
-- never gets set and phase 8 falls back to the old fixed-delay/attempt-
-- counter behavior unchanged. Not verified against a live client -- watch
-- //df status and the chat log to confirm it's actually catching the message.
windower.register_event('incoming text', function(original, modified)
    if not state.running then return end
    if state.phase ~= 8 then return end
    local text = modified or original
    if not text or not text:find('found!', 1, true) then return end

    if text:find('Retrying', 1, true) then
        -- Superwarp is already retrying this call on its own; make sure our
        -- watchdog doesn't also fire underneath its retry loop, and don't
        -- stack a second command from our side on the next tick.
        state.sw_signal = 'retrying'
        mark_progress()
    else
        -- Superwarp gave up on this attempt. Wake the main loop up on the
        -- very next frame instead of leaving it to wait out the rest of the
        -- fixed 15s delay before phase 8 gets a chance to retry.
        state.sw_signal = 'failed'
        nexttime = os.clock()
        delay = 0
    end
    state.sw_signal_at = os.time()
end)

-- Menu-open packets for every NPC we interact with directly: the
-- Dimensional Portal (phase 2), the Domain Invasion NPC (phase 3) and the
-- Undulating Confluence (phase 9). Reads Menu ID / Zone / Menu Parameters
-- from the packet itself rather than hardcoding them.
windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)
    if injected or blocked then return end

    -- Menu-selection acknowledgement for the ack-aware action queue
    -- (run_action_queue), used by phase 4's Elvorseal/warp-to-arena
    -- sequence. Not blocked -- the client's own menu state should still see
    -- it; we're just listening in to know when it's safe to fire the next
    -- selection.
    if id == 0x05C then
        if state.running and state.ack_wait_gen and state.ack_wait_gen == state.seq_gen then
            local resume = state.ack_resume
            state.ack_wait_gen = nil
            state.ack_resume   = nil
            if resume then resume() end
        end
        return
    end

    if id ~= 0x032 and id ~= 0x034 then return end
    if not state.running then return end
    if state.phase ~= 2 and state.phase ~= 3 and state.phase ~= 9 then return end

    local npc = state.approach_npc
    if not npc then return end

    local parsed = packets.parse('incoming', modified or original)
    if not parsed or parsed['NPC'] ~= npc.id then return end

    local menu_id = parsed['Menu ID']
    local zone_id = parsed['Zone'] or get_zone_id()
    if not menu_id or not zone_id then return end

    if state.phase == 2 then
        -- Dimensional Portal: select the Reisenjima warp option, then
        -- release the menu after a beat.
        packets.inject(packets.new('outgoing', 0x05B, {
            ['Target']            = npc.id,
            ['Target Index']      = npc.index,
            ['Option Index']      = 0,
            ['Automated Message'] = true,
            ['Zone']              = zone_id,
            ['Menu ID']           = menu_id,
        }))
        coroutine.schedule(function()
            packets.inject(packets.new('outgoing', 0x05B, {
                ['Target']            = npc.id,
                ['Target Index']      = npc.index,
                ['Option Index']      = 2,
                ['Automated Message'] = false,
                ['Zone']              = zone_id,
                ['Menu ID']           = menu_id,
            }))
        end, 0.5)

    elseif state.phase == 3 then
        state.domain_menu = {
            npc         = npc,
            zone        = zone_id,
            menu_id     = menu_id,
            menu_params = parsed['Menu Parameters'],
        }
        set_phase(4, 'Domain NPC menu captured')

    elseif state.phase == 9 then
        state.confluence_menu = {npc = npc, zone = zone_id, menu_id = menu_id}
        set_phase(10, 'Confluence menu captured')
    end

    return true   -- block the client-side menu so it cannot race our response
end)

-- ==========================================================================
-- COMMANDS
-- ==========================================================================
local function cmd_start(zone_arg)
    local zone_id = get_zone_id()
    if not zone_id then
        -- Client still loading/zoning right as the command came in. Retrying
        -- beats routing on a nil zone, which reroute_from_reality can only
        -- resolve by defaulting to the Warp Ring -- wrong regardless of what
        -- the actual target is (e.g. Reisenjima needs the Dim. Ring, not a
        -- warp home).
        log('Zone not yet known (loading/zoning?); retrying //df start in 2s...')
        coroutine.schedule(function() cmd_start(zone_arg) end, 2)
        return
    end

    state.fail_reason      = nil
    state.arena_positioned = false
    state.waypoint_index   = 1
    state.death_latched    = false
    state.elvorseal_fails  = 0
    state.selected_tp_ring = nil      -- re-scan rings on every start
    reset_arena_tracking()
    state.hud_note         = nil
    state.last_seen_zone   = nil      -- force a settle window on the first tick
    state.settle_until     = nil
    state.watchdog_recoveries = 0
    state.last_recovery_zone  = nil
    state.unknown_zone_since  = nil
    state.approach_npc        = nil
    state.approach_best_dist  = nil
    state.domain_menu         = nil
    state.confluence_menu     = nil
    state.wp_path_done        = false
    state.sw_signal           = nil
    state.sw_signal_at        = nil
    state.sw_last_sent_at     = nil
    if hud then hud:show() end

    -- No explicit target and we are already standing in a DI zone: farm THIS
    -- zone rather than warping out to go to Reisenjima (the most common
    -- "stuck in phase 3" report came from exactly this situation).
    if zone_arg == nil and zone_id then
        if     zone_id == ZONES.zitah then zone_arg = 'zitah'
        elseif zone_id == ZONES.ruaun then zone_arg = 'ruaun' end
        if zone_arg then log('No target given; adopting the current zone (' .. zone_arg .. ').') end
    end

    local function resume(zone_idx, boss_label)
        state.zone_index = zone_idx
        state.phase = 0   -- force set_phase to treat the next phase as a fresh transition
        if zone_id == target_zone_id() then
            log('Already in zone for ' .. boss_label .. '. Resuming on the spot.')
        else
            log('Not yet in zone for ' .. boss_label .. '. Routing from ' .. zone_name_of(zone_id) .. '...')
        end
        reroute_from_reality(zone_id, 'start')
    end

    if zone_arg == 'zitah' then
        resume(2, "Azi Dahaka (Zi'Tah)")
    elseif zone_arg == 'ruaun' then
        resume(3, "Naga Raja (Ru'Aun)")
    elseif zone_arg == nil or zone_arg == 'reisenjima' or zone_arg == 'reisen' then
        resume(1, 'Quetzalcoatl (Reisenjima)')
    else
        error('Unknown zone "' .. zone_arg .. '". Valid: reisenjima | zitah | ruaun')
        return
    end

    state.running = true
    nexttime = os.clock()
    delay = 1
    log('DomainFarm started. NOTE: the Superwarp addon must be loaded for Home Point warps (Zi\'Tah/Ru\'Aun legs).')
    update_hud()
end

-- Restart travel for the CURRENT rotation target from wherever we are.
local function cmd_resume()
    local idx = state.zone_index
    local arg = (idx == 2 and 'zitah') or (idx == 3 and 'ruaun') or 'reisenjima'
    log('Resuming with target ' .. arg .. '...')
    cmd_start(arg)
end

local function cmd_status()
    local target = rotation[state.zone_index]
    log('Status : ' .. (state.running and 'RUNNING' or 'PAUSED'))
    log('Target : ' .. (target and target.label or 'None'))
    log('Phase  : ' .. (PHASE_NAMES[state.phase] or tostring(state.phase))
        .. ('  (%ds in phase)'):format(os.time() - state.phase_started_at))
    log('Zone   : ' .. zone_name_of(get_zone_id()))
    if state.last_transition then log('Last transition: ' .. state.last_transition) end
    log(('Watchdog recoveries used: %d/%d'):format(state.watchdog_recoveries, settings.watchdog_recoveries))
    if state.fail_reason then log('Last failure: ' .. state.fail_reason) end
end

local function cmd_help()
    log('DomainFarm commands:')
    log('  //df start [reisenjima|zitah|ruaun]  - start (default: reisenjima)')
    log('  //df stop                            - stop and reset all state')
    log('  //df resume                          - restart travel for the current target from here')
    log('  //df status                          - print current state')
    log('  //df mark                            - log current x/y as a waypoint')
    log('  //df help                            - this text')
end

windower.register_event('addon command', function(...)
    local args = {...}
    local cmd  = args[1] and args[1]:lower() or 'help'

    if cmd == 'stop' then
        stop_bot(nil)
        state.fail_reason = nil
        if hud then hud:hide() end
        log('DomainFarm stopped and state reset.')

    elseif cmd == 'start' then
        cmd_start(args[2] and args[2]:lower() or nil)

    elseif cmd == 'resume' then
        cmd_resume()

    elseif cmd == 'status' then
        cmd_status()

    elseif cmd == 'mark' then
        local me = windower.ffxi.get_mob_by_target('me')
        if me then
            log(('Waypoint: {x = %.2f, y = %.2f}'):format(me.x, me.y))
        else
            error('Cannot mark: player entity unavailable (zoning?).')
        end

    else
        cmd_help()
    end
end)

windower.register_event('unload', function()
    stop_running()
    if hud then hud:destroy() end
end)
