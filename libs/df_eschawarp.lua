--[[
    libs/df_eschawarp.lua

    Native packet sequences for the two Escha NPC interactions that used to
    be handed off to Superwarp ("sw ew domain" / "sw ew enter"). Home Point
    warping ("sw hp") is intentionally NOT covered here and stays on
    Superwarp -- see DomainFarm.lua's header comment for why.

    Ported from Superwarp's map/escha.lua (Akaden, BSD-3-Clause; copyright
    notice preserved per license). Each function below cites the source
    lines it's based on. These are pure builder functions: given a captured
    menu snapshot, they return packets/action lists to send. They do not
    call packets.inject themselves and touch no DomainFarm state -- the
    caller (DomainFarm.lua) decides when/how to fire them.

    v11.2: build_domain_sequence()'s steps are now marked with wait_ack,
    matching map/escha.lua's wait_packet=0x05C on nearly every step exactly
    (only Option Index 14 has none in the source). DomainFarm.lua's
    run_action_queue() waits for the real incoming 0x05C before firing the
    next menu selection, instead of a guessed fixed delay. That guess was
    the reported bug: interacting with Affi (Escha-Zi'Tah) never warped to
    the arena, because a later menu selection was firing before the server
    had processed the previous one, in a menu system that appears to care
    about that ordering strictly. build_enter_sequence() is unchanged and
    still uses fixed delays -- the source shows no wait_packet dependency
    for that command, and the actual zone change is confirmed independently
    by DomainFarm's reality router anyway.

    NOT verified against a live client:
      - read_domain_status()'s bit offsets (dragon_state, has_elvorseal) are
        copied verbatim from map/escha.lua's `domain` sub-command.
    Watch //df status and the chat log on the next live run to confirm.
]]

local packets = require('packets')

local M = {}

-- NPC names to search for, per interaction (map/escha.lua's npc_names
-- table). Trimmed to only what DomainFarm's rotation actually reaches --
-- La Theine/Konschtat/Tahrongi crag routing and the Reisenjima Sanctorium
-- exit aren't part of this rotation (Reisenjima is reached via the existing
-- native Dimensional Portal handling), so those names are left out.
M.DOMAIN_NPC_NAMES     = {'Affi', 'Dremi', 'Shiftrix'}
M.CONFLUENCE_NPC_NAMES = {'Undulating Confluence'}

-- Same-zone "warp to battle" landing spot per DI zone (map/escha.lua's
-- `domain` sub-command, zone==288/289/291 branches). This is a genuine
-- in-zone teleport, not a real zone change; DomainFarm's own arena
-- waypoints (libs/df_waypoints.lua) cover the short remaining walk from
-- here to the actual boss engagement point.
local ARENA_LANDING = {
    [288] = {x = -2,  z = 0,                 y =  59.500003814697, rotation =  63, unknown1 = 12}, -- Escha - Zi'Tah
    [289] = {x =  0,  z = -43.600002288818,  y = -238.00001525879, rotation = 191, unknown1 = 12}, -- Escha - Ru'Aun
    [291] = {x = 640, z = -372.00003051758,  y = -921.00006103516, rotation =  95, unknown1 = 12}, -- Reisenjima
}

-- Shorthand for the 0x05B "menu select" packet shape used throughout
-- map/escha.lua's sub-commands.
local function menu_select(npc, option_index, zone, menu_id, automated, unknown1)
    return packets.new('outgoing', 0x05B, {
        ['Target']            = npc.id,
        ['Target Index']      = npc.index,
        ['Option Index']      = option_index,
        ['Automated Message'] = automated,
        ['_unknown1']         = unknown1 or 0,
        ['_unknown2']         = 0,
        ['Zone']              = zone,
        ['Menu ID']           = menu_id,
    })
end

-- Reads the two Domain Invasion status bits out of the menu snapshot's
-- "Menu Parameters" field (map/escha.lua's `domain` sub-command, lines
-- ~291-292). dragon_state 0 or 3 = not ready; has_elvorseal = buff already
-- active, in which case the Elvorseal request steps are skipped.
function M.read_domain_status(menu_params)
    local dragon_state  = menu_params:unpack('b2', 1)
    local has_elvorseal = menu_params:unpack('b8', 4) == 0x80
    return dragon_state, has_elvorseal
end

function M.domain_not_ready(dragon_state)
    return dragon_state == 0 or dragon_state == 3
end

-- Cancels the Domain menu outright (map/escha.lua sends this same shape for
-- "dragon not ready" / Silt / unlock failures).
function M.build_domain_cancel(menu)
    return menu_select(menu.npc, 0, menu.zone, menu.menu_id, false, 16384)
end

-- Builds the ordered {packet, delay} sequence for "request Elvorseal if
-- needed, then warp to the arena" (map/escha.lua's `domain` sub-command,
-- args == {} / {'enter'} branch). Returns nil if the zone has no known
-- landing spot -- shouldn't happen for the three DI zones, but this fails
-- loudly rather than teleporting to (0,0,0) if that data ever needs an
-- update.
function M.build_domain_sequence(menu, has_elvorseal)
    local npc, zone, menu_id = menu.npc, menu.zone, menu.menu_id
    local landing = ARENA_LANDING[zone]
    if not landing then return nil end

    local seq = {}
    -- wait_ack mirrors map/escha.lua's wait_packet=0x05C exactly: every step
    -- here needs the real server acknowledgement before the next menu
    -- selection means what we think it means, EXCEPT Option Index 14, which
    -- the source fires with no wait_packet at all. `delay` is only used as
    -- a small settle buffer for the non-acked step; acked steps advance on
    -- the ack itself (see run_action_queue in DomainFarm.lua), with `delay`
    -- unused for them.
    local function step(packet, wait_ack, delay)
        seq[#seq + 1] = {packet = packet, wait_ack = wait_ack, delay = delay}
    end

    step(menu_select(npc, 14, zone, menu_id, true), false, 0.5)  -- init menu (no ack in the source)
    step(menu_select(npc, 8,  zone, menu_id, true), true)        -- init menu
    step(menu_select(npc, 9,  zone, menu_id, true), true)        -- init menu
    if not has_elvorseal then
        step(menu_select(npc, 9,  zone, menu_id, true), true)    -- request Elvorseal
        step(menu_select(npc, 10, zone, menu_id, true), true)    -- confirm request
    end
    step(menu_select(npc, 11, zone, menu_id, true), true)        -- confirm teleport

    local move = packets.new('outgoing', 0x05C, {
        ['Target ID']    = npc.id,
        ['Target Index'] = npc.index,
        ['Zone']         = zone,
        ['Menu ID']      = menu_id,
        ['X']            = landing.x,
        ['Z']            = landing.z,
        ['Y']            = landing.y,
        ['_unknown1']    = landing.unknown1,
        ['Rotation']     = landing.rotation,
    })
    step(move, true)                                       -- same-zone move to the arena
    step(menu_select(npc, 12, zone, menu_id, false), true)  -- close menu

    return seq
end

-- Builds the {packet, delay} sequence for entering Escha-Zi'Tah / Escha-
-- Ru'Aun from the Qufim/Misareaux conflux (map/escha.lua's `enter` sub-
-- command). Both zones use Option Index 1; the crag-portal branch (Option
-- Index 2, for La Theine/Konschtat/Tahrongi) isn't needed here since
-- DomainFarm reaches Reisenjima via its own native Dimensional Portal
-- handling instead.
function M.build_enter_sequence(menu)
    local npc, zone, menu_id = menu.npc, menu.zone, menu.menu_id
    local update_request = packets.new('outgoing', 0x016, {
        ['Target Index'] = windower.ffxi.get_player().index,
    })
    return {
        {packet = update_request,                            wait_ack = false, delay = 0.3},
        {packet = menu_select(npc, 0, zone, menu_id, true),  wait_ack = false, delay = 1.0},
        {packet = menu_select(npc, 1, zone, menu_id, false), wait_ack = false, delay = 0},
    }
end

return M
