_addon.author   = 'Zforninja'
_addon.version  = '8.6'
_addon.commands = {'domainfarm', 'DomainFarm'}

require 'logger'
require 'strings'
require('coroutine')
require('texts') -- Required for HUD
packets = require('packets')
res = require('resources')

-- State Machine Variables
local nexttime = os.clock()
local delay = 0
local pause = 'on'
local fighting = false
local tp = false
local elvorseal_timer = 0
local arena_positioned = false

-- 1: Reisenjima (Quetz), 2: Escha-Zi'Tah (Azi), 3: Escha-Ru'Aun (Naga)
local current_zone_index = 1 
local bot_phase = 0 
local waypoint_index = 1

local teleport_ring = "Dim. Ring (Dem)"
local warp_ring = "Warp Ring"

-- ==========================================
-- HUD CONFIGURATION
-- ==========================================
local hud_settings = {
    pos = {x = 10, y = 10},
    bg = {alpha = 200, red = 0, green = 0, blue = 0},
    text = {size = 10, font = 'Consolas', stroke = {width = 1, alpha = 255, red = 0, green = 0, blue = 0}},
    flags = {bold = true, draggable = true}
}
local hud = texts.new(hud_settings)
hud:show()

local zone_names = {
    [1] = "Reisenjima (Quetzalcoatl)",
    [2] = "Escha - Zi'Tah (Azi Dahaka)",
    [3] = "Escha - Ru'Aun (Naga Raja)"
}

local phase_names = {
    [0] = "Idle",
    [1] = "Equipping Teleport Ring",
    [2] = "Navigating to Reisenjima Portal",
    [3] = "Pathing to Elvorseal NPC",
    [4] = "Requesting Elvorseal (Superwarp)",
    [5] = "Verifying Elvorseal Buff",
    [6] = "Arena Combat / Wait",
    [7] = "Equipping Warp Ring",
    [8] = "Safe Zone - Warping to Conflux",
    [9] = "Pathing to Escha Conflux",
    [10] = "Entering Escha Zone"
}

local function update_hud()
    local status_text = pause == 'on' and "\\cs(255,100,100)[PAUSED]\\cr" or "\\cs(100,255,100)[RUNNING]\\cr"
    local target_text = "\\cs(100,200,255)" .. (zone_names[current_zone_index] or "None") .. "\\cr"
    local action_text = "\\cs(255,255,100)" .. (phase_names[bot_phase] or "Idle") .. "\\cr"
    
    hud:text('  DomainFarm ' .. status_text .. '  \n  Target: ' .. target_text .. '  \n  Action: ' .. action_text .. '  ')
end

-- Town/Safe Zones for Auto-Correction
local safe_zones = {
    ['Western Adoulin']=true, ['Eastern Adoulin']=true, ['Celennia Memorial Library']=true,
    ['Ru\'Lude Gardens']=true, ['Upper Jeuno']=true, ['Lower Jeuno']=true, ['Port Jeuno']=true,
    ['Mhaura']=true, ['Selbina']=true, ['Rabao']=true, ['Kazham']=true, ['Norg']=true,
    ['Southern San d\'Oria']=true, ['Northern San d\'Oria']=true, ['Port San d\'Oria']=true,
    ['Bastok Mines']=true, ['Bastok Markets']=true, ['Port Bastok']=true, ['Metalworks']=true,
    ['Windurst Waters']=true, ['Windurst Walls']=true, ['Port Windurst']=true, ['Windurst Woods']=true
}

-- Waypoint Paths
local q_waypoints = { {x = -212.00, y = 94.00}, {x = -207.61, y = 88.76}, {x = -203.64, y = 84.19}, {x = -201.26, y = 81.52}, {x = -203.09, y = 77.94} }
local m_waypoints = { {x = -66.00, y = 562.00}, {x = -65.22, y = 565.10}, {x = -63.39, y = 568.49}, {x = -60.10, y = 570.39}, {x = -56.77, y = 569.21}, {x = -52.69, y = 567.83}, {x = -50.37, y = 567.07}, {x = -49.57, y = 570.27} }
local zitah_waypoints = { {x = -345.43, y = -178.93}, {x = -349.69, y = -175.19}, {x = -353.34, y = -171.91}, {x = -355.45, y = -171.26} }
local ruaun_waypoints = { {x = -0.37, y = -466.98}, {x = -4.43, y = -463.94}, {x = -9.29, y = -460.63} }

-- Arena Flanking Paths
local zitah_arena_wps = { {x = -6.77, y = 52.33}, {x = -7.74, y = 44.74}, {x = -8.40, y = 39.76}, {x = -9.19, y = 33.85} }
local ruaun_arena_wps = { {x = 2.25, y = -223.03}, {x = 5.04, y = -217.67}, {x = 6.67, y = -212.86}, {x = 8.38, y = -211.61} }

-- Trust Configuration Table
local trust_list = {
    {spell = 'Ulmia', alt = 'Arciella II'},
    {spell = 'Qultada', alt = ''},
    {spell = 'Koru-Moru', alt = ''},
    {spell = 'Joachim', alt = 'Lilisette'},
    {spell = 'Sylvie (UC)', alt = 'Prishe II'}
}

local function isBuffActive(id)
    local self = windower.ffxi.get_player()
    if not self or not self.buffs then return false end
    for _, v in pairs(self.buffs) do
        if v == id then return true end
    end
    return false
end

local function can_act()
    local bad_buffs = {2, 6, 7, 16, 17, 28, 29}
    for _, buff_id in ipairs(bad_buffs) do
        if isBuffActive(buff_id) then return false end
    end
    return true
end

local function getEquippedItem(slot_name)
    local inventory = windower.ffxi.get_items()
    local equipment = inventory['equipment']
    if not equipment or not equipment[slot_name] then return "" end
    local bag = equipment[string.format('%s_bag', slot_name)]
    local item = windower.ffxi.get_items(bag, equipment[slot_name])
    if not item or not item.id then return "" end
    return res.items:with('id', item.id).en
end

local function process_ring(ring_name)
    local right_ring = getEquippedItem('right_ring')
    local left_ring = getEquippedItem('left_ring')
    if right_ring ~= ring_name and left_ring ~= ring_name then
        windower.send_command('input /equip ring2 "'..ring_name..'"')
        delay = 4
    else
        windower.send_command('input /item "'..ring_name..'" <me>')
        delay = 15 -- Ring cast time + wait for zone. Auto-retries if interrupted.
    end
end

local function get_missing_trust()
    local party = windower.ffxi.get_party()
    if party.p5 then return false end
    
    local spellrecasts = windower.ffxi.get_spell_recasts()
    local known_spells = windower.ffxi.get_spells()
    
    for _, t_info in ipairs(trust_list) do
        local found = false
        for i, v in pairs(party) do
            if string.match(i, 'p[0-5]') and v.mob and (v.mob.name == t_info.spell or v.mob.name == t_info.alt) then 
                found = true 
                break 
            end
        end
        
        if not found then
            local primary_data = res.spells:with('en', t_info.spell)
            if primary_data and known_spells[primary_data.id] and spellrecasts[primary_data.recast_id] == 0 then 
                return t_info.spell 
            end
            
            if t_info.alt and t_info.alt ~= '' then
                local alt_data = res.spells:with('en', t_info.alt)
                if alt_data and known_spells[alt_data.id] and spellrecasts[alt_data.recast_id] == 0 then
                    return t_info.alt
                end
            end
        end
    end
    return false
end

-- Custom mob finder to bypass invisible placeholder/dummy indices
local function get_dragon(mob_name)
    for _, mob in pairs(windower.ffxi.get_mob_array()) do
        if mob.name == mob_name and mob.valid_target then
            return mob
        end
    end
    return nil
end

local function executePath(waypoints, target_phase)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return end
    
    local wp = waypoints[waypoint_index]
    if not wp then
        windower.ffxi.run(false)
        if target_phase == 10 then windower.send_command('sw') end
        bot_phase = target_phase
        delay = 3
        return
    end
    
    local dist = math.sqrt((wp.x - me.x)^2 + (wp.y - me.y)^2)
    if dist > 2 then
        windower.ffxi.run(wp.x - me.x, wp.y - me.y)
        delay = 0.1
    else
        waypoint_index = waypoint_index + 1
    end
end

local function executeArenaPath(waypoints)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return false end
    
    local wp = waypoints[waypoint_index]
    if not wp then
        windower.ffxi.run(false)
        return true
    end
    
    local dist = math.sqrt((wp.x - me.x)^2 + (wp.y - me.y)^2)
    if dist > 2 then
        windower.ffxi.run(wp.x - me.x, wp.y - me.y)
        delay = 0.1
        return false
    else
        waypoint_index = waypoint_index + 1
        return false
    end
end

windower.register_event('prerender', function()
    update_hud() -- Update the display text every tick
    
    local curtime = os.clock()
    if nexttime + delay > curtime or pause == 'on' then return end
    nexttime = curtime
    delay = 0.2
    
    local info = windower.ffxi.get_info()
    if not info or not info.zone then return end
    local zone_name = res.zones[info.zone].name
    local player = windower.ffxi.get_player()
    if not player then return end

    -- ==========================================
    -- STRICT SELF-HEALING ENFORCEMENT
    -- ==========================================
    if safe_zones[zone_name] then
        -- Only phases 1, 7, and 8 are allowed in safe zones
        if bot_phase > 1 and bot_phase < 7 then
            log('Detected safe zone. Auto-correcting mismatched phase...')
            fighting = false
            if current_zone_index == 1 then bot_phase = 1 else bot_phase = 8 end
        end
    elseif zone_name == 'Qufim Island' or zone_name == 'Misareaux Coast' then
        if bot_phase ~= 8 and bot_phase ~= 9 and bot_phase ~= 10 then
            waypoint_index = 1
            bot_phase = 9
        end
    elseif zone_name == 'La Theine Plateau' or zone_name == 'Konschtat Highlands' or zone_name == 'Tahrongi Canyon' then
        if bot_phase ~= 2 then bot_phase = 2 end
    elseif zone_name == 'Reisenjima' then
        if bot_phase == 1 or bot_phase == 2 then 
            windower.ffxi.run(false)
            bot_phase = 4 
        end
    elseif zone_name == 'Escha - Zi\'Tah' or zone_name == 'Escha - Ru\'Aun' then
        if bot_phase == 8 or bot_phase == 9 or bot_phase == 10 or bot_phase < 3 or bot_phase > 7 then
            waypoint_index = 1
            bot_phase = 3
        end
    end

    -- ==========================================
    -- PHASE EXECUTION
    -- ==========================================
    
    -- Phase 1: Equipping and casting Teleport Ring to reset for Reisenjima
    if bot_phase == 1 then
        process_ring(teleport_ring)
        
    -- Phase 2: At Crag, navigating to Reisenjima Portal
    elseif bot_phase == 2 then
        local me = windower.ffxi.get_mob_by_target('me')
        tp = windower.ffxi.get_mob_by_name('Dimensional Portal')
        if tp and math.sqrt(tp.distance) > 3 then
            windower.ffxi.run(tp.x - me.x, tp.y - me.y)
        elseif tp and math.sqrt(tp.distance) <= 3 then
            windower.ffxi.run(false)
            local p = packets.new('outgoing', 0x01A, { ['Target'] = tp.id, ['Target Index'] = tp.index })
            packets.inject(p)
            delay = 5
        end

    -- Phase 3: Pathing to NPCs (Affi / Dremi)
    elseif bot_phase == 3 then
        if current_zone_index == 2 then executePath(zitah_waypoints, 4)
        elseif current_zone_index == 3 then executePath(ruaun_waypoints, 4) end

    -- Phase 4: Firing //sw ew domain at NPC
    elseif bot_phase == 4 then
        windower.send_command('sw ew domain')
        elvorseal_timer = os.clock()
        bot_phase = 5
        delay = 5

    -- Phase 5: Checking Elvorseal Buff (603) and 60s cooldown loop
    elseif bot_phase == 5 then
        if isBuffActive(603) then
            bot_phase = 6
            arena_positioned = false 
            waypoint_index = 1       
        elseif os.clock() - elvorseal_timer > 10 then
            log('Elvorseal rejected or on cooldown. Retrying in 60 seconds.')
            delay = 60
            bot_phase = 4
        end

    -- Phase 6: Arena Fighting & Buffing
    elseif bot_phase == 6 then
        local mob_name = "Quetzalcoatl"
        if current_zone_index == 2 then mob_name = "Azi Dahaka"
        elseif current_zone_index == 3 then mob_name = "Naga Raja" end
        
        -- Safely bypasses invisible dummy spawns
        local target_mob = get_dragon(mob_name)
        
        -- Kill Confirmed Loop
        if target_mob and target_mob.hpp > 0 then
            fighting = true
        elseif fighting then
            fighting = false
            windower.ffxi.run(false)
            log(mob_name .. ' defeated or despawned.')
            
            if current_zone_index == 1 then
                current_zone_index = 2
                bot_phase = 7
            elseif current_zone_index == 2 then
                current_zone_index = 3
                bot_phase = 7
            elseif current_zone_index == 3 then
                current_zone_index = 1
                bot_phase = 1
            end
            return
        end

        -- Elvorseal Buff Check & Instant Death Handler
        if not isBuffActive(603) then
            fighting = false 
            if player.status > 1 then
                log('Player died. Returning to Home Point to reset the loop...')
                delay = 8 -- 8 seconds gives the client time to register the death animation
                packets.inject(packets.new('outgoing', 0x01A, { ['Target'] = player.id, ['Target Index'] = player.index, ['Category'] = 0x0D }))
            else
                bot_phase = 4
            end
            return
        end

        -- Pre-Fight Trust Summoning & Positioning
        if not fighting and player.status == 0 then
            local me = windower.ffxi.get_mob_by_target('me')
            
            if current_zone_index == 1 and (math.abs(612.17 - me.x) > 2 or math.abs(-933.43 - me.y) > 2) then
                windower.ffxi.run(612.17 - me.x, -933.43 - me.y)
            elseif current_zone_index == 2 and not arena_positioned then
                arena_positioned = executeArenaPath(zitah_arena_wps)
            elseif current_zone_index == 3 and not arena_positioned then
                arena_positioned = executeArenaPath(ruaun_arena_wps)
            else
                windower.ffxi.run(false) 
                local next_trust = get_missing_trust()
                if next_trust and can_act() then
                    windower.send_command('input /ma "'..next_trust..'" <me>')
                    delay = 6
                end
            end
        end

        -- Active Combat Logic
        if player.status == 0 and fighting then
            local engage = packets.new('outgoing', 0x01A, { ['Target'] = target_mob.id, ['Target Index'] = target_mob.index, ['Category'] = 0x02 })
            packets.inject(engage)
            delay = 1
        elseif target_mob and math.sqrt(target_mob.distance) > 7 and player.status == 1 and fighting then
            local target = windower.ffxi.get_mob_by_index(player.target_index or 0)
            local self_vector = windower.ffxi.get_mob_by_index(player.index or 0)
            if target and self_vector then
                local angle = (math.atan2((target.y - self_vector.y), (target.x - self_vector.x))*180/math.pi)*-1
                windower.ffxi.turn((angle):radian())
                windower.ffxi.run(true)
            end
        elseif target_mob and math.sqrt(target_mob.distance) <= 7 and player.status == 1 and fighting then
            windower.ffxi.run(false)
            if not windower.ffxi.get_party().p5 then
                local next_trust = get_missing_trust()
                if next_trust and can_act() then
                    windower.send_command('input /ma "'..next_trust..'" <me>')
                    delay = 6
                end
            end
        end

    -- Phase 7: Equipping and casting Warp Ring
    elseif bot_phase == 7 then
        process_ring(warp_ring)
        
    -- Phase 8: Waiting in Safe Zone to Superwarp to Confluxes
    elseif bot_phase == 8 then
        if safe_zones[zone_name] then
            if current_zone_index == 2 then windower.send_command('sw qufim')
            elseif current_zone_index == 3 then windower.send_command('sw misareaux') end
            delay = 10 -- Retry command every 10s if we fail to zone
        end
        
    -- Phase 9: Pathing to Escha Conflux
    elseif bot_phase == 9 then
        if current_zone_index == 2 then executePath(q_waypoints, 10)
        elseif current_zone_index == 3 then executePath(m_waypoints, 10) end
        
    -- Phase 10: Waiting to enter Escha Zone via Superwarp
    elseif bot_phase == 10 then
        if zone_name == 'Qufim Island' or zone_name == 'Misareaux Coast' then
            windower.send_command('sw')
            delay = 10 -- Retry command every 10s if we fail to zone
        end
    end
end)

windower.register_event('zone change', function(new_id, old_id)
    -- Pauses script to allow client resources to load. Self-healing detects the new zone.
    delay = 8
end)

windower.register_event('incoming chunk', function(id, data)
    -- Dimensional Portal Menu Interaction
    if id == 0x034 or id == 0x032 then
        if bot_phase == 2 then
            local parse = packets.parse('incoming', data)
            if tp and parse['NPC'] == tp.id then
                local zone_id = windower.ffxi.get_info().zone
                local zone_name = res.zones[zone_id].name
                local menu_id = (zone_name == 'La Theine Plateau') and 222 or 926
                
                packets.inject(packets.new('outgoing', 0x05B, { ["Target"] = tp.id, ["Option Index"] = 0, ["Target Index"] = tp.index, ["Automated Message"] = true, ["Zone"] = zone_id, ["Menu ID"] = menu_id }))
                packets.inject(packets.new('outgoing', 0x05B, { ["Target"] = tp.id, ["Option Index"] = 2, ["Target Index"] = tp.index, ["Automated Message"] = false, ["Zone"] = zone_id, ["Menu ID"] = menu_id }))
            end
        end
    end
end)

windower.register_event('addon command', function(...)
    local command = {...}
    if command[1] == 'stop' then
        pause = 'on'
        bot_phase = 0
        fighting = false
        windower.ffxi.run(false)
        log('DomainFarm sequence aborted and states reset.')
    elseif command[1] == 'start' then
        pause = 'off'
        arena_positioned = false
        waypoint_index = 1
        
        if command[2] and string.lower(command[2]) == 'zitah' then
            current_zone_index = 2
            bot_phase = 7
            log('Starting at Azi Dahaka (Zi\'Tah). Self-healing module will detect zone...')
        elseif command[2] and string.lower(command[2]) == 'ruaun' then
            current_zone_index = 3
            bot_phase = 7
            log('Starting at Naga Raja (Ru\'Aun). Self-healing module will detect zone...')
        else
            current_zone_index = 1
            bot_phase = 1
            log('Starting at Quetzalcoatl (Reisenjima). Self-healing module will detect zone...')
        end
        
    elseif command[1] == 'mark' then
        local me = windower.ffxi.get_mob_by_target('me')
        log('Waypoint: {x = ' .. string.format("%.2f", me.x) .. ', y = ' .. string.format("%.2f", me.y) .. '}')
    end
end)

windower.register_event('unload', function()
    if hud then hud:destroy() end
end)