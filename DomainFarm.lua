--[[
    DomainFarm v10.4 (hardened rewrite)
    Automated Domain Invasion farming for Windower 4.

    Rotation: Reisenjima (Quetzalcoatl) -> Escha-Zi'Tah (Azi Dahaka)
              -> Escha-Ru'Aun (Naga Raja) -> repeat.

    Bonus targets: Mireu can spawn in any of the three arenas; it is added to
    every zone's target list and fought when present (see settings.bonus_targets).

    Hard external dependency: the Superwarp addon must be loaded
    (used for Elvorseal requests, home-point warps and conflux entry).

    This rewrite fixes every issue documented in domainfarm_analysis.md:
      - all nil-dereference crash sites guarded (player/me/party/res lookups)
      - no dependency on the unloaded 'maths' library (no (n):radian())
      - menu automation reads Menu ID / Zone from the parsed packet instead
        of hardcoding 222/926, ignores injected chunks, blocks the client
        menu, and staggers the release packet
      - death detected only on status 2/3 (never cutscenes), one-shot latch
      - disengage before ring/warp phases
      - per-phase watchdog timeouts: the bot can no longer spin forever on
        a missing ring, uncharged enchant, failed Elvorseal, missing portal,
        unrecognized zone, geometry snag or a silently-failing Superwarp
      - waypoint index reset on every phase change (centralized set_phase)
      - stuck-movement detection on all pathing
      - zone routing by zone ID (resolved from resources at load), not by
        name-string comparison at runtime
      - party fullness via party1_count, not the p5 proxy
      - explicit stop/pause on logout; movement halted on unload
      - zone confirmation gate: NPC/mob phases only run in their expected zone
      - post-zone settling window (HUD: "Zone settling...") before entity use
      - phase-specific watchdogs (combat 1200s, transit 300s, menus 120s)
      - coordinate-based chase via get_mob_by_id vectors (TargetLock-independent)
]]

_addon.name     = 'DomainFarm'
_addon.author   = 'Zforninja (hardened rewrite)'
_addon.version  = '10.4'
_addon.commands = {'domainfarm', 'df'}

require('logger')
local packets = require('packets')
local res     = require('resources')

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
    -- Superwarp command strings (adjust if your Superwarp version differs)
    sw_elvorseal    = 'sw ew domain',      -- request Elvorseal at the eschan portal
    sw_qufim        = 'sw hp qufim island',    -- explicit Home Point warp (avoids Survival Guide ambiguity)
    sw_misareaux    = 'sw hp misareaux coast',  -- explicit Home Point warp (avoids Survival Guide ambiguity)
    sw_enter_escha  = 'sw ew enter',        -- enter Escha via Eschan portal (per Superwarp docs)
    engage_range    = 7,                   -- melee range check (yalms)
    waypoint_range  = 2,                   -- waypoint arrival tolerance (yalms)
    elvorseal_buff  = 603,                 -- buff ID for Elvorseal
    elvorseal_retry = 60,                  -- seconds between Elvorseal retries
    elvorseal_max   = 5,                   -- consecutive failures before giving up
    ring_timeout    = 120,                 -- seconds before a ring phase is declared failed
    stuck_timeout   = 12,                  -- seconds without movement progress = stuck
    zone_settle     = 4,                   -- seconds to wait after arriving in a zone before touching entities
    movement_mode   = 'vector',            -- 'vector' = windower.ffxi.run(dx, dy); 'heading' = run(radians)
    -- Bonus Domain Invasion targets that can appear in ANY of the three zones.
    -- Mireu has a small chance to spawn alongside the zone boss; we fight it too.
    bonus_targets   = {'Mireu'},
    post_kill_linger = 45,                 -- seconds to keep scanning for another target after a kill
}

-- Phase-specific watchdog timeouts (seconds). Combat/arena phases must tolerate
-- the 15+ minute wait for a Domain Invasion boss to spawn; transit phases are
-- stuck if they take 5 minutes; teleport/menu phases are stuck after 2 minutes.
local PHASE_TIMEOUTS = {
    [1]  = 120,    -- teleport ring
    [2]  = 120,    -- dimensional portal menu
    [3]  = 300,    -- pathing to eschan portal
    [4]  = 1200,   -- requesting elvorseal (arena)
    [5]  = 1200,   -- verifying elvorseal (arena)
    [6]  = 1200,   -- combat / waiting for boss spawn
    [7]  = 120,    -- warp ring
    [8]  = 120,    -- superwarp from safe zone
    [9]  = 300,    -- pathing to undulating confluence
    [10] = 120,    -- superwarp escha entry
    [11] = 300,    -- dead / home point
}

-- Trust lineup: primary spell with optional alternate.
local trust_list = {
    {spell = 'Ulmia',       alt = 'Arciela II'},
    {spell = 'Qultada',     alt = nil},
    {spell = 'Koru-Moru',   alt = nil},
    {spell = 'Joachim',     alt = 'Lilisette'},
    {spell = 'Sylvie (UC)', alt = 'Prishe II'},
}

-- ==========================================================================
-- ZONE RESOLUTION (name -> ID at load; runtime routing is ID-based)
-- ==========================================================================
local function zone_id_of(name)
    local z = res.zones:with('en', name)
    if not z then
        warning(('Zone "%s" not found in resources; routing for it is disabled.'):format(name))
        return nil
    end
    return z.id
end

local ZONES = {
    reisenjima = zone_id_of('Reisenjima'),
    zitah      = zone_id_of('Escha - Zi\'Tah'),
    ruaun      = zone_id_of('Escha - Ru\'Aun'),
    la_theine  = zone_id_of('La Theine Plateau'),
    konschtat  = zone_id_of('Konschtat Highlands'),
    tahrongi   = zone_id_of('Tahrongi Canyon'),
    qufim      = zone_id_of('Qufim Island'),
    misareaux  = zone_id_of('Misareaux Coast'),
}

-- Safe zones (towns) where ring/superwarp phases may execute.
local safe_zone_names = {
    'Western Adoulin', 'Eastern Adoulin', 'Celennia Memorial Library',
    'Ru\'Lude Gardens', 'Upper Jeuno', 'Lower Jeuno', 'Port Jeuno',
    'Mhaura', 'Selbina', 'Rabao', 'Kazham', 'Norg',
    'Southern San d\'Oria', 'Northern San d\'Oria', 'Port San d\'Oria',
    'Bastok Mines', 'Bastok Markets', 'Port Bastok', 'Metalworks',
    'Windurst Waters', 'Windurst Walls', 'Port Windurst', 'Windurst Woods',
    'Chocobo Circuit', 'Mog Garden',
}
local safe_zone_ids = {}
for _, name in ipairs(safe_zone_names) do
    local id = zone_id_of(name)
    if id then safe_zone_ids[id] = true end
end

-- Crag-teleport zones (where the Dimensional Portal to Reisenjima stands)
local portal_zone_ids = {}
for _, key in ipairs({'la_theine', 'konschtat', 'tahrongi'}) do
    if ZONES[key] then portal_zone_ids[ZONES[key]] = true end
end

-- Conflux tunnel zones
local conflux_zone_ids = {}
if ZONES.qufim     then conflux_zone_ids[ZONES.qufim]     = true end
if ZONES.misareaux then conflux_zone_ids[ZONES.misareaux] = true end

-- ==========================================================================
-- ROTATION / TARGET DATA
-- ==========================================================================
-- 1: Reisenjima (Quetzalcoatl), 2: Escha-Zi'Tah (Azi Dahaka), 3: Escha-Ru'Aun (Naga Raja)
local rotation = {
    [1] = {label = 'Reisenjima (Quetzalcoatl)',   zone = ZONES.reisenjima, boss = 'Quetzalcoatl'},
    [2] = {label = "Escha - Zi'Tah (Azi Dahaka)", zone = ZONES.zitah,      boss = 'Azi Dahaka'},
    [3] = {label = "Escha - Ru'Aun (Naga Raja)",  zone = ZONES.ruaun,      boss = 'Naga Raja'},
}

-- Build each zone's full target list: primary boss + every bonus target
-- (Mireu). `targets` is a name->true set for O(1) lookups during mob scans.
for _, entry in pairs(rotation) do
    entry.targets = {[entry.boss] = true}
    for _, name in ipairs(settings.bonus_targets) do
        entry.targets[name] = true
    end
end

-- Waypoint paths (x/y pairs)
local q_waypoints      = { {x=-212.00, y= 94.00}, {x=-207.61, y= 88.76}, {x=-203.64, y= 84.19}, {x=-201.26, y= 81.52}, {x=-203.09, y= 77.94} }
local m_waypoints      = { {x= -66.00, y=562.00}, {x= -65.22, y=565.10}, {x= -63.39, y=568.49}, {x= -60.10, y=570.39}, {x= -56.77, y=569.21}, {x= -52.69, y=567.83}, {x= -50.37, y=567.07}, {x= -49.57, y=570.27} }
local zitah_waypoints  = { {x=-345.43, y=-178.93}, {x=-349.69, y=-175.19}, {x=-353.34, y=-171.91}, {x=-355.45, y=-171.26} }
local ruaun_waypoints  = { {x=  -0.37, y=-466.98}, {x=  -4.43, y=-463.94}, {x=  -9.29, y=-460.63} }
local zitah_arena_wps  = { {x=  -6.77, y=  52.33}, {x=  -7.74, y=  44.74}, {x=  -8.40, y=  39.76}, {x=  -9.19, y=  33.85} }
local ruaun_arena_wps  = { {x=   2.25, y=-223.03}, {x=   5.04, y=-217.67}, {x=   6.67, y=-212.86}, {x=   8.38, y=-211.61} }
local reisen_arena     = {x = 612.17, y = -933.43}

-- Arena anchor per rotation index (used for the target scan radius). For
-- Zi'Tah / Ru'Aun the anchor is the final arena waypoint.
rotation[1].arena = reisen_arena
rotation[2].arena = zitah_arena_wps[#zitah_arena_wps]
rotation[3].arena = ruaun_arena_wps[#ruaun_arena_wps]

-- ==========================================================================
-- STATE
-- ==========================================================================
local PHASE_NAMES = {
    [0]  = 'Idle / Stopped',
    [1]  = 'Equipping / Using Teleport Ring',
    [2]  = 'Navigating to Dimensional Portal',
    [3]  = 'Pathing to Eschan Portal',
    [4]  = 'Requesting Elvorseal',
    [5]  = 'Verifying Elvorseal Buff',
    [6]  = 'Arena Combat & Trusts',
    [7]  = 'Equipping / Using Warp Ring',
    [8]  = 'Safe Zone - Superwarping',
    [9]  = 'Pathing to Undulating Confluence',
    [10] = 'Entering Escha Zone',
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
    last_kill_at       = nil,          -- os.time() of the most recent kill (linger window anchor)
    kills              = 0,            -- kills this arena visit
    bonus_seen         = {},           -- bonus target names already announced this visit
    arena_positioned   = false,
    portal             = nil,          -- Dimensional Portal entity snapshot
    elvorseal_sent_at  = nil,          -- os.time() of last Elvorseal request
    elvorseal_fails    = 0,
    ring_started_at    = nil,          -- os.time() when the current ring phase began
    ring_equip_sent    = false,
    selected_tp_ring   = nil,          -- which Dim. Ring was picked for this cycle
    phase_started_at   = os.time(),    -- watchdog anchor
    death_latched      = false,        -- home-point packet sent once per death
    sw_attempts        = 0,            -- superwarp retry counter for phases 8/10
    last_pos           = nil,          -- {x, y, t} for stuck detection
    fail_reason        = nil,          -- surfaced on the HUD
    last_unhandled_zone = nil,
    last_seen_zone     = nil,          -- zone ID observed on the previous tick
    settle_until       = nil,          -- os.time() before which entity interaction is forbidden
    hud_note           = nil,          -- transient status line (settling / zone gate)
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
    windower.ffxi.run(false)
    if reason then
        state.fail_reason = reason
        error(reason)   -- logger's error(): prints in red, does not raise
    end
    update_hud()
end

-- Central phase transition: resets everything a stale phase could poison.
local function set_phase(p)
    if state.phase ~= p then
        state.phase            = p
        state.phase_started_at = os.time()
        state.waypoint_index   = 1
        state.last_pos         = nil
        state.sw_attempts      = 0
        if p == 1 or p == 7 then
            state.ring_started_at = nil
            state.ring_equip_sent = false
        end
        if p == 4 then
            state.elvorseal_sent_at = nil
        end
        if p ~= 6 then
            state.arena_positioned = false
        end
    end
end

local function get_zone_id()
    local info = windower.ffxi.get_info()
    if not info or not info.zone or info.zone == 0 then return nil end
    return info.zone
end

local function zone_name_of(id)
    local z = id and res.zones[id]
    return z and z.name or ('Zone #' .. tostring(id or '?'))
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
    -- FFXI heading: 0 = +X, increasing clockwise when viewed from above;
    -- Windower's run(radians)/turn(radians) accept this convention directly.
    return math.atan2(dy, dx)
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
    -- 0 = inventory, 8 = wardrobe, 10-12 = wardrobes 2-4 (equippable bags)
    for _, bag in ipairs({0, 8, 10, 11, 12}) do
        local contents = windower.ffxi.get_items(bag)
        if contents then
            for i = 1, (contents.max or 0) do
                local it = contents[i]
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
-- TRUSTS
-- ==========================================================================
local function get_missing_trust()
    local party = windower.ffxi.get_party()
    if not party then return nil end
    if (party.party1_count or 0) >= 6 then return nil end

    local recasts = windower.ffxi.get_spell_recasts() or {}
    local known   = windower.ffxi.get_spells() or {}

    for _, t in ipairs(trust_list) do
        local present = false
        for i = 0, 5 do
            local member = party['p' .. i]
            if member and member.mob
               and (member.mob.name == t.spell or (t.alt and member.mob.name == t.alt)) then
                present = true
                break
            end
        end

        if not present then
            for _, name in ipairs({t.spell, t.alt}) do
                if name and name ~= '' then
                    local spell = res.spells:with('en', name)
                    if spell and known[spell.id]
                       and (recasts[spell.recast_id] or 0) == 0 then
                        return name
                    end
                end
            end
        end
    end
    return nil
end

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
--   * Sticky: if our cached target is still alive we keep it (no ping-pong
--     between the boss and Mireu when both are up).
--   * Otherwise scan the mob array for any live mob whose name is in the
--     zone's target set. Names are unique DI bosses, so no radius filter is
--     applied (the dragons roam far across the arena).
--   * Prefer a mob already claimed by us, then the closest to the arena anchor.
-- Announces the first sighting of a bonus target (Mireu) once per visit.
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
            log(('%s spawned! Adding it to the fight.'):format(best.name))
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
    state.last_kill_at       = nil
    state.kills              = 0
    state.bonus_seen         = {}
end

-- ==========================================================================
-- PATHING
-- ==========================================================================
-- Walks `waypoints`; on completion runs `on_complete` (optional) and switches
-- to `target_phase`. Returns nothing; manages delay itself.
local function executePath(waypoints, target_phase, on_complete)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return end

    local wp = waypoints[state.waypoint_index]
    if not wp then
        stop_running()
        if on_complete then on_complete() end
        set_phase(target_phase)
        delay = 3
        return
    end

    local dist = math.sqrt((wp.x - me.x)^2 + (wp.y - me.y)^2)
    if dist > settings.waypoint_range then
        if movement_stuck(me) then
            stop_running()
            stop_bot('Movement stuck while pathing (waypoint ' .. state.waypoint_index .. '). Bot stopped.')
            return
        end
        run_towards(wp.x - me.x, wp.y - me.y)
        delay = 0.1
    else
        state.waypoint_index = state.waypoint_index + 1
        state.last_pos = nil
    end
end

-- Arena flanking path; returns true once complete.
local function executeArenaPath(waypoints)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return false end

    local wp = waypoints[state.waypoint_index]
    if not wp then
        stop_running()
        return true
    end

    local dist = math.sqrt((wp.x - me.x)^2 + (wp.y - me.y)^2)
    if dist > settings.waypoint_range then
        if movement_stuck(me) then
            stop_running()
            -- Don't hard-stop mid-combat setup; just accept current position.
            log('Stuck on arena path; holding position here.')
            return true
        end
        run_towards(wp.x - me.x, wp.y - me.y)
        delay = 0.1
        return false
    else
        state.waypoint_index = state.waypoint_index + 1
        state.last_pos = nil
        return false
    end
end

-- ==========================================================================
-- ZONE REALITY ROUTER (ID-based)
-- ==========================================================================
local function enforce_zone_reality(zone_id)
    -- Dead-recovery (phase 11) may only be rerouted once we reach a safe zone;
    -- no other branch is allowed to yank the bot out of it.
    if state.phase == 11 and not safe_zone_ids[zone_id] then return end

    if safe_zone_ids[zone_id] then
        if state.phase == 11 then
            -- Arrived at home point after death: restart travel.
            state.death_latched = false
            state.fighting = false
            set_phase(state.zone_index == 1 and 1 or 8)
        elseif state.phase > 1 and state.phase < 7 then
            log('Reality check: in a safe zone with a combat phase active. Resetting transit state.')
            state.fighting = false
            set_phase(state.zone_index == 1 and 1 or 8)
        elseif state.phase == 7 then
            set_phase(8)
        end

    elseif conflux_zone_ids[zone_id] then
        if state.phase ~= 9 and state.phase ~= 10 then
            set_phase(9)
        end

    elseif portal_zone_ids[zone_id] then
        if state.phase ~= 2 then set_phase(2) end

    elseif zone_id == ZONES.reisenjima then
        if state.phase == 1 or state.phase == 2 then
            stop_running()
            set_phase(4)
        end

    elseif zone_id == ZONES.zitah or zone_id == ZONES.ruaun then
        -- Allow 7 (warp ring) to run; anything outside 3..7 gets rerouted.
        if state.phase < 3 or state.phase > 7 then
            set_phase(isBuffActive(settings.elvorseal_buff) and 6 or 3)
        end

    else
        if state.last_unhandled_zone ~= zone_id then
            warning(('Unrecognized zone "%s" at phase %d. Add it to safe_zone_names if it is a valid start/home point.')
                    :format(zone_name_of(zone_id), state.phase))
            state.last_unhandled_zone = zone_id
        end
        -- Watchdog (below) will pause the bot if we linger here.
    end
end

-- ==========================================================================
-- PHASE HANDLERS
-- ==========================================================================
local function phase_2_portal()
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return end

    state.portal = windower.ffxi.get_mob_by_name('Dimensional Portal')
    local portal = state.portal
    if not portal then
        -- Portal beyond tracking range: warn once via watchdog rather than spin silently.
        delay = 2
        return
    end

    local dist = math.sqrt(portal.distance or 0)
    if dist > 3 then
        if movement_stuck(me) then
            stop_running()
            stop_bot('Stuck while approaching the Dimensional Portal. Bot stopped.')
            return
        end
        run_towards(portal.x - me.x, portal.y - me.y)
        delay = 0.1
    else
        stop_running()
        local p = packets.new('outgoing', 0x01A, {
            ['Target']       = portal.id,
            ['Target Index'] = portal.index,
            ['Category']     = 0,          -- NPC interaction
        })
        packets.inject(p)
        delay = 5
    end
end

local function phase_4_request_elvorseal()
    windower.send_command(settings.sw_elvorseal)
    state.elvorseal_sent_at = os.time()
    set_phase(5)
    delay = 5
end

local function phase_5_verify_elvorseal()
    if isBuffActive(settings.elvorseal_buff) then
        state.elvorseal_fails = 0
        set_phase(6)
        return
    end
    if state.elvorseal_sent_at and os.time() - state.elvorseal_sent_at > 10 then
        state.elvorseal_fails = state.elvorseal_fails + 1
        if state.elvorseal_fails >= settings.elvorseal_max then
            stop_bot(('Elvorseal failed %d times (event inactive / daily cap / Superwarp missing?). Bot stopped.')
                     :format(state.elvorseal_fails))
            return
        end
        log(('Elvorseal not detected (attempt %d/%d). Retrying in %ds.')
            :format(state.elvorseal_fails, settings.elvorseal_max, settings.elvorseal_retry))
        delay = settings.elvorseal_retry
        set_phase(4)
    end
end

local function advance_rotation()
    if state.zone_index == 1 then
        state.zone_index = 2
        set_phase(7)
    elseif state.zone_index == 2 then
        state.zone_index = 3
        set_phase(7)
    else
        state.zone_index = 1
        state.selected_tp_ring = nil   -- re-scan rings next cycle (charges may have changed)
        set_phase(1)
    end
    reset_arena_tracking()
end

local function handle_death(player)
    state.fighting = false
    stop_running()
    if not state.death_latched then
        state.death_latched = true
        log('Player died. Returning to Home Point...')
        set_phase(11)
        delay = 8
    end
end

local function phase_11_dead(player)
    if player.status ~= 2 and player.status ~= 3 then
        -- Raised or already back up: hand control back to the router.
        state.death_latched = false
        set_phase(state.zone_index == 1 and 1 or 8)
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
        -- Confirmed gone: count the kill and open the linger window.
        state.fighting = false
        state.boss_missing_since = nil
        state.kills = state.kills + 1
        state.last_kill_at = now
        stop_running()
        log(('%s defeated or despawned. Scanning %ds for another target (Mireu)...')
            :format(state.target_name or target.boss, settings.post_kill_linger))
        state.boss_id = nil
        state.target_name = nil
        state.hud_note = 'Post-kill scan for additional targets...'
        if player.status == 1 then
            -- Disengage so we can re-engage a new target (or use a ring later).
            windower.send_command('input /attack off')
            delay = 3
        end
        return
    elseif state.last_kill_at then
        -- Linger window after a kill: nothing alive right now. Keep scanning
        -- until the window expires, then the arena is clear -> move on.
        if now - state.last_kill_at < settings.post_kill_linger then
            delay = 1
            return
        end
        state.hud_note = nil
        log(('Arena clear (%d kill%s). Moving on.'):format(state.kills, state.kills == 1 and '' or 's'))
        if player.status == 1 then
            windower.send_command('input /attack off')
            delay = 3
            return
        end
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
            state.arena_positioned = executeArenaPath(zitah_arena_wps)
        elseif state.zone_index == 3 and not state.arena_positioned then
            state.arena_positioned = executeArenaPath(ruaun_arena_wps)
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
            local engage = packets.new('outgoing', 0x01A, {
                ['Target']       = boss.id,
                ['Target Index'] = boss.index,
                ['Category']     = 2,          -- engage
            })
            packets.inject(engage)
            delay = 1
        elseif result == 'stuck' then
            log('Stuck while closing on ' .. (boss.name or target.boss) .. '; engaging from here.')
            state.last_pos = nil
            local engage = packets.new('outgoing', 0x01A, {
                ['Target']       = boss.id,
                ['Target Index'] = boss.index,
                ['Category']     = 2,
            })
            packets.inject(engage)
            delay = 1
        else
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
    if not safe_zone_ids[zone_id] then return end
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
    delay = 15
end

local function phase_10_enter_escha(zone_id)
    if not conflux_zone_ids[zone_id] then return end
    state.sw_attempts = state.sw_attempts + 1
    if state.sw_attempts > 6 then
        stop_bot('Escha entry via Superwarp is not zoning us (is Superwarp loaded / Eschan portal unlocked?). Bot stopped.')
        return
    end
    windower.send_command(settings.sw_enter_escha)
    delay = 15
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
        -- Eschan portal pathing, Elvorseal and combat: only in THE target zone.
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

    -- Global death check (any phase).
    if (player.status == 2 or player.status == 3) and state.phase ~= 11 then
        handle_death(player)
        return
    end

    enforce_zone_reality(zone_id)

    -- Phase-specific watchdog.
    local timeout = PHASE_TIMEOUTS[state.phase]
    if timeout and state.phase > 0 and os.time() - state.phase_started_at > timeout then
        stop_bot(('Watchdog: phase "%s" exceeded %ds without progress. Bot stopped.')
                 :format(PHASE_NAMES[state.phase] or state.phase, timeout))
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
    -- eschan portal while still standing in Qufim).
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
    elseif p == 2  then phase_2_portal()
    elseif p == 3  then
        if     state.zone_index == 2 then executePath(zitah_waypoints, 4)
        elseif state.zone_index == 3 then executePath(ruaun_waypoints, 4) end
    elseif p == 4  then phase_4_request_elvorseal()
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
    elseif p == 9  then
        if     state.zone_index == 2 then executePath(q_waypoints, 10, function() windower.send_command(settings.sw_enter_escha) end)
        elseif state.zone_index == 3 then executePath(m_waypoints, 10, function() windower.send_command(settings.sw_enter_escha) end) end
    elseif p == 10 then phase_10_enter_escha(zone_id)
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
    state.portal          = nil
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

-- NPC menu automation for the Dimensional Portal (phase 2).
windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)
    if injected or blocked then return end
    if id ~= 0x032 and id ~= 0x034 then return end
    if not state.running or state.phase ~= 2 then return end

    local portal = state.portal
    if not portal then return end

    local parsed = packets.parse('incoming', modified or original)
    if not parsed or parsed['NPC'] ~= portal.id then return end

    -- Use the authoritative values carried by the menu packet itself.
    local menu_id = parsed['Menu ID']
    local zone_id = parsed['Zone'] or get_zone_id()
    if not menu_id or not zone_id then return end

    -- Select the Reisenjima warp option, then release the menu after a beat.
    packets.inject(packets.new('outgoing', 0x05B, {
        ['Target']            = portal.id,
        ['Target Index']      = portal.index,
        ['Option Index']      = 0,
        ['Automated Message'] = true,
        ['Zone']              = zone_id,
        ['Menu ID']           = menu_id,
    }))
    coroutine.schedule(function()
        packets.inject(packets.new('outgoing', 0x05B, {
            ['Target']            = portal.id,
            ['Target Index']      = portal.index,
            ['Option Index']      = 2,
            ['Automated Message'] = false,
            ['Zone']              = zone_id,
            ['Menu ID']           = menu_id,
        }))
    end, 0.5)

    return true   -- block the client-side menu so it cannot race our response
end)

-- ==========================================================================
-- COMMANDS
-- ==========================================================================
local function cmd_start(zone_arg)
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
    if hud then hud:show() end

    local zone_id = get_zone_id()

    local function resume(zone_idx, escha_zone_id, travel_phase, in_zone_no_buff_phase, boss_label)
        state.zone_index = zone_idx
        if zone_id and zone_id == escha_zone_id then
            if isBuffActive(settings.elvorseal_buff) then
                set_phase(6)
                state.fighting = false
                log('Already at ' .. boss_label .. ' with Elvorseal active. Resuming combat directly.')
            else
                set_phase(in_zone_no_buff_phase)
                log('Already in zone for ' .. boss_label .. ' without Elvorseal. Requesting/pathing now.')
            end
        else
            set_phase(travel_phase)
            log('Not yet in zone for ' .. boss_label .. '. Router will manage transit...')
        end
    end

    if zone_arg == 'zitah' then
        resume(2, ZONES.zitah, 7, 3, "Azi Dahaka (Zi'Tah)")
    elseif zone_arg == 'ruaun' then
        resume(3, ZONES.ruaun, 7, 3, "Naga Raja (Ru'Aun)")
    elseif zone_arg == nil or zone_arg == 'reisenjima' or zone_arg == 'reisen' then
        resume(1, ZONES.reisenjima, 1, 4, 'Quetzalcoatl (Reisenjima)')
    else
        error('Unknown zone "' .. zone_arg .. '". Valid: reisenjima | zitah | ruaun')
        return
    end

    state.running = true
    nexttime = os.clock()
    delay = 1
    log('DomainFarm started. NOTE: the Superwarp addon must be loaded for travel to work.')
    update_hud()
end

local function cmd_status()
    local target = rotation[state.zone_index]
    log('Status : ' .. (state.running and 'RUNNING' or 'PAUSED'))
    log('Target : ' .. (target and target.label or 'None'))
    log('Phase  : ' .. (PHASE_NAMES[state.phase] or tostring(state.phase)))
    if state.fail_reason then log('Last failure: ' .. state.fail_reason) end
end

local function cmd_help()
    log('DomainFarm commands:')
    log('  //df start [reisenjima|zitah|ruaun]  - start (default: reisenjima)')
    log('  //df stop                            - stop and reset all state')
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
