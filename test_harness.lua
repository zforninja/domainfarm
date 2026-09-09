-- Smoke-test harness: stubs the Windower 4 environment and drives DomainFarm.lua
-- through load, start/stop/status/mark commands, prerender ticks in several
-- zones, a death, a zone change, and an incoming menu chunk.

local events = {}

-- Windower runs Lua 5.1 (math.atan2 / unpack exist). Newer interpreters used
-- to run this harness (5.3+/LuaJIT via lupa) may lack them; shim for the harness only.
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
unpack = unpack or table.unpack

-- Virtual clock so the addon's os.clock/os.time throttles can be advanced.
local vtime = 1000
os.clock = function() return vtime end
os.time  = function() return vtime end

-- ---------- resource stubs ----------
local function make_dict(entries)
    local d = {}
    for _, e in ipairs(entries) do d[e.id] = e end
    return setmetatable(d, {__index = {
        with = function(self, key, val)
            for _, e in pairs(d) do
                if type(e) == 'table' and e[key] == val then return e end
            end
            return nil
        end
    }})
end

local zones = make_dict({
    {id=291, en='Reisenjima', name='Reisenjima'},
    {id=288, en="Escha - Zi'Tah", name="Escha - Zi'Tah"},
    {id=289, en="Escha - Ru'Aun", name="Escha - Ru'Aun"},
    {id=102, en='La Theine Plateau', name='La Theine Plateau'},
    {id=108, en='Konschtat Highlands', name='Konschtat Highlands'},
    {id=117, en='Tahrongi Canyon', name='Tahrongi Canyon'},
    {id=126, en='Qufim Island', name='Qufim Island'},
    {id=25,  en='Misareaux Coast', name='Misareaux Coast'},
    {id=244, en='Upper Jeuno', name='Upper Jeuno'},
    {id=245, en='Lower Jeuno', name='Lower Jeuno'},
    {id=246, en='Port Jeuno', name='Port Jeuno'},
    {id=243, en="Ru'Lude Gardens", name="Ru'Lude Gardens"},
    {id=256, en='Western Adoulin', name='Western Adoulin'},
    {id=257, en='Eastern Adoulin', name='Eastern Adoulin'},
    {id=284, en='Celennia Memorial Library', name='Celennia Memorial Library'},
    {id=249, en='Mhaura', name='Mhaura'}, {id=248, en='Selbina', name='Selbina'},
    {id=247, en='Rabao', name='Rabao'}, {id=250, en='Kazham', name='Kazham'},
    {id=252, en='Norg', name='Norg'},
    {id=230, en="Southern San d'Oria", name="Southern San d'Oria"},
    {id=231, en="Northern San d'Oria", name="Northern San d'Oria"},
    {id=232, en="Port San d'Oria", name="Port San d'Oria"},
    {id=234, en='Bastok Mines', name='Bastok Mines'},
    {id=235, en='Bastok Markets', name='Bastok Markets'},
    {id=236, en='Port Bastok', name='Port Bastok'},
    {id=237, en='Metalworks', name='Metalworks'},
    {id=238, en='Windurst Waters', name='Windurst Waters'},
    {id=239, en='Windurst Walls', name='Windurst Walls'},
    {id=240, en='Port Windurst', name='Port Windurst'},
    {id=241, en='Windurst Woods', name='Windurst Woods'},
    {id=70, en='Chocobo Circuit', name='Chocobo Circuit'},
    {id=280, en='Mog Garden', name='Mog Garden'},
})

local items = make_dict({
    {id=28540, en='Dim. Ring (Dem)'},
    {id=28541, en='Warp Ring'},
    {id=1, en='Copper Ring'},
})

local spells = make_dict({
    {id=1017, en='Ulmia', recast_id=1017},
    {id=1030, en='Arciela II', recast_id=1030},
    {id=1018, en='Qultada', recast_id=1018},
    {id=1019, en='Koru-Moru', recast_id=1019},
    {id=1020, en='Joachim', recast_id=1020},
    {id=1021, en='Lilisette', recast_id=1021},
    {id=1022, en='Sylvie (UC)', recast_id=1022},
    {id=1023, en='Prishe II', recast_id=1023},
})

-- ---------- world state (mutable by the test) ----------
local world = {
    zone = 245,                -- Lower Jeuno
    player = {id=1000, index=10, status=0, buffs={255, 0}},
    me = {x=0, y=0, z=0},
    mobs = {},                 -- id -> mob
    party = {party1_count=1, p0={mob={name='TestChar'}}},
    sent_commands = {},
    injected = {},
}

-- ---------- library stubs ----------
package.loaded['resources'] = {zones=zones, items=items, spells=spells,
    buffs=make_dict({{id=603, en='Elvorseal'}})}
package.loaded['packets'] = {
    new = function(dir, id, fields) return {dir=dir, id=id, fields=fields or {}} end,
    inject = function(p) table.insert(world.injected, p) end,
    parse = function(dir, data) return data end,   -- tests pass parsed tables directly
    build = function(p) return '' end,
}
package.loaded['logger'] = true
function log(...) print('[log]', ...) end
function warning(...) print('[warn]', ...) end
function error(...) print('[err]', ...) end  -- logger overrides error() in Windower
package.loaded['texts'] = {
    new = function() return {
        show=function() end, hide=function() end,
        text=function() end, destroy=function() end} end,
}

coroutine.schedule = function(fn, t) fn() end  -- run scheduled work immediately

_addon = {}

windower = {
    register_event = function(name, fn) events[name] = fn end,
    send_command = function(cmd) table.insert(world.sent_commands, cmd) end,
    ffxi = {
        get_info = function() return {zone = world.zone, logged_in = true} end,
        get_player = function() return world.player end,
        get_party = function() return world.party end,
        get_items = function(bag, index)
            if bag == nil then
                return {equipment = world.equipment or {right_ring=0, right_ring_bag=0, left_ring=0, left_ring_bag=0}}
            end
            if index then
                local b = world.bags and world.bags[bag]
                return b and b[index] or nil
            end
            local b = world.bags and world.bags[bag]
            return b or {max=0}
        end,
        get_mob_by_target = function(t) return world.me end,
        get_mob_by_name = function(n)
            for _, m in pairs(world.mobs) do if m.name == n then return m end end
        end,
        get_mob_by_id = function(id) return world.mobs[id] end,
        get_mob_array = function() return world.mobs end,
        get_spell_recasts = function() return {[1017]=0,[1018]=0,[1019]=0,[1020]=0,[1022]=0} end,
        get_spells = function() return {[1017]=true,[1018]=true,[1019]=true,[1020]=true,[1022]=true} end,
        run = function(...) world.last_run = {...} end,
        turn = function(...) end,
    },
}

-- ---------- load the addon ----------
local ok, err = pcall(dofile, 'DomainFarm.lua')
assert(ok, 'ADDON FAILED TO LOAD: ' .. tostring(err))
print('== addon loaded OK ==')

local function tick(n, dt)
    for _ = 1, (n or 1) do
        vtime = vtime + (dt or 10)   -- advance past any delay gate
        local ok2, e2 = pcall(events['prerender'])
        assert(ok2, 'prerender crashed: ' .. tostring(e2))
    end
end

local function cmd(...)
    local ok2, e2 = pcall(events['addon command'], ...)
    assert(ok2, 'addon command crashed: ' .. tostring(e2))
end

-- 1. help / status / mark before start
cmd('help'); cmd('status'); cmd('mark')

-- 2. mark with no player entity (was a crash in v9.1)
local saved_me = world.me; world.me = nil
cmd('mark')
world.me = saved_me
print('== mark nil-guard OK ==')

-- 3. start with a bad zone arg (was silent default in v9.1)
cmd('start', 'zitha')

-- 4. start default: ring not in inventory -> must stop with a message, not loop
world.bags = {[0] = {max = 2, [1] = {id = 1, count = 1}}}
cmd('start')
tick(3)
print('== missing-ring stop OK ==')

-- 5. put the ring in inventory and start again; expect /equip command
world.bags = {[0] = {max = 2, [1] = {id = 28540, count = 1}}}
world.equipment = {right_ring=0, right_ring_bag=0, left_ring=0, left_ring_bag=0}
cmd('start')
tick(2)
local saw_equip = false
for _, c in ipairs(world.sent_commands) do
    if c:find('/equip', 1, true) then saw_equip = true end
end
assert(saw_equip, 'expected an /equip command in phase 1')
print('== phase 1 equip OK ==')

-- 6. simulate zoning with zone id 0 mid-transition (was a crash in v9.1)
world.zone = 0
tick(3)
world.zone = 108  -- Konschtat Highlands (Dem)
events['zone change'](108, 245)
tick(2)           -- delay=8 gates; force timer forward by ticking anyway (no crash expected)
print('== zone-0 guard OK ==')

-- 7. phase 2 with no 'me' entity (was a crash in v9.1)
world.me = nil
tick(2)
world.me = {x=0, y=0}
print('== phase-2 me nil-guard OK ==')

-- 8. incoming menu chunk while portal not yet acquired (must not crash)
local r = events['incoming chunk'](0x034, {NPC=999, ['Menu ID']=926, Zone=108}, nil, false, false)
assert(r == nil, 'handler must ignore chunks before portal acquisition')
-- injected chunks must be ignored
r = events['incoming chunk'](0x034, {NPC=999, ['Menu ID']=926, Zone=108}, nil, true, false)
assert(r == nil, 'handler must ignore injected chunks')
print('== menu handler guards OK ==')

-- 9. jump to Escha Zi'Tah with Elvorseal, spawn boss, verify combat path
world.zone = 288
events['zone change'](288, 108)
world.player.buffs = {603}
world.mobs = {[5000] = {id=5000, index=50, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=-9, y=30, distance=100}}
cmd('start', 'zitah')
tick(5)
print('== combat phase ticks OK ==')

-- 10. engaged chase branch (this crashed v9.1 via (angle):radian())
world.player.status = 1
world.player.target_index = 50
tick(3)
print('== chase branch OK (no maths-lib crash) ==')

-- 11. death handling: status 2, must latch phase 11 and inject 0x0D once per cadence
world.player.status = 2
tick(2)
local found_0d = false
for _, p in ipairs(world.injected) do
    if p.id == 0x01A and p.fields and p.fields['Category'] == 0x0D then
        assert(p.fields['Param'] == 0, 'Param must be explicit 0')
        found_0d = true
    end
end
assert(found_0d, 'expected reraise-dialogue packet after death')
print('== death handling OK ==')

-- 12. cutscene status must NOT be treated as death
world.injected = {}
world.player.status = 4
world.player.buffs = {}
cmd('start', 'zitah')  -- re-arm
tick(3)
for _, p in ipairs(world.injected) do
    assert(not (p.id == 0x01A and p.fields['Category'] == 0x0D),
           'cutscene status 4 must not trigger the death packet')
end
print('== cutscene-not-death OK ==')


-- ---------------------------------------------------------------------------
-- v10.1 additions: zone gate, settling, phase watchdogs, coordinate chase
-- ---------------------------------------------------------------------------

-- 14. SETTLING: after a zone change, first ticks must not touch entities.
world.zone = 288; world.player.status = 0; world.player.buffs = {603}
world.mobs = {[5000] = {id=5000, index=50, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=30, y=30, distance=900}}
world.injected = {}; world.sent_commands = {}; world.last_run = nil
cmd('start', 'zitah')
events['zone change'](288, 126)
tick(1, 9)                      -- past the 8s zone-change delay, inside 4s settle? (8+? see below)
-- zone change sets settle_until = t+4 and delay = 8; first tick at t+9 is already settled.
-- Force a fresh settle by changing the observed zone id and ticking within the window:
world.zone = 289                -- Ru'Aun observed unexpectedly -> new settle window
tick(1, 1)
assert(world.last_run == nil or world.last_run[1] == false, 'no movement during settle window')
assert(#world.injected == 0, 'no packets during settle window')
print('== settling blocks entity interaction OK ==')

-- 15. WRONG DI ZONE: target is Zi'Tah but we stand in Ru'Aun (289). v10.5: the
--     router must never touch the boss here; it switches to the Warp Ring (7).
world.bags = {[0] = {max = 3, [1] = {id = 28540, count = 1}, [2] = {id = 28541, count = 1}}}
world.sent_commands = {}
tick(1, 5)                      -- settle expired; router: wrong DI zone -> phase 7
tick(2, 1)
assert(#world.injected == 0, 'must not engage anything in the wrong zone')
local saw_warp_equip = false
for _, c in ipairs(world.sent_commands) do
    if c:find('/equip', 1, true) and c:find('Warp Ring', 1, true) then saw_warp_equip = true end
end
assert(saw_warp_equip, 'wrong DI zone must trigger the Warp Ring escape (phase 7)')
print('== wrong DI zone -> warp home OK ==')

-- 16. Back in the right zone (e.g. the user ran there) -> router puts us in
--     combat -> settle -> coordinate chase runs toward the boss.
cmd('stop')
world.zone = 288
cmd('start', 'zitah')
tick(1, 5); tick(1, 5)          -- first tick arms the settle window, second clears it
tick(2, 1)                      -- phase 6; boss visible at (30,30), me at (0,0)
assert(world.last_run and world.last_run[1] ~= false,
       'expected a run() toward the boss coordinates')
local dx, dy = world.last_run[1], world.last_run[2]
assert(dx and dy and dx > 0 and dy > 0, 'run vector must point toward boss at (+30,+30)')
print('== coordinate-based chase OK ==')

-- 17. Arrive in range -> engage packet injected (status 0 -> Category 2).
world.mobs[5000].x, world.mobs[5000].y = 3, 3
tick(2, 1)
local engaged = false
for _, p in ipairs(world.injected) do
    if p.id == 0x01A and p.fields['Category'] == 2 then engaged = true end
end
assert(engaged, 'expected engage packet once within range')
print('== engage on arrival OK ==')

-- 18. PHASE WATCHDOG: combat phase must survive > 300s with no boss (spawn wait),
--     but must stop after 1200s.
cmd('stop')
world.mobs = {}                 -- no boss yet
world.zone = 288; world.player.buffs = {603}
cmd('start', 'zitah')           -- phase 6, arena
tick(1, 5)                      -- settle
tick(1, 400)                    -- 400s with no spawn: old 300s watchdog would have fired
-- is the bot still running? (state is local; infer from behaviour: a later tick still moves/acts)
world.mobs = {[5001] = {id=5001, index=51, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=40, y=0, distance=1600}}
world.last_run = nil
tick(2, 1)
assert(world.last_run and world.last_run[1] ~= false,
       'bot must still be running after 400s in combat phase (1200s watchdog)')
print('== combat watchdog >300s OK ==')

world.mobs = {}
world.last_run = nil
tick(1, 1300)                   -- exceed 1200s with no boss -> soft recovery #1 (fresh window)
world.mobs = {[5002] = {id=5002, index=52, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=40, y=0, distance=1600}}
tick(2, 1)
assert(world.last_run and world.last_run[1] ~= false,
       'v10.5: first watchdog trip must soft-recover, not stop')
world.mobs = {}
tick(1, 1300)                   -- recovery #2
tick(1, 1300)                   -- budget exhausted -> hard stop
world.mobs = {[5002] = {id=5002, index=52, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=40, y=0, distance=1600}}
world.last_run = nil
tick(2, 1)
assert(world.last_run == nil or world.last_run[1] == false,
       'bot must stop once the soft-recovery budget is exhausted')
print('== combat watchdog soft-recovery then stop OK ==')

-- 19. Transit watchdog stays at 300s (phase 9 pathing in Qufim).
world.zone = 126; world.player.buffs = {}
world.me = {x=0, y=0}           -- far from first Qufim waypoint, never moves -> stuck logic aside,
cmd('start', 'zitah')           -- travel phase 7 -> router in Qufim -> phase 9
tick(1, 5)
-- disable stuck detection effect by moving 'me' each tick so only the watchdog can stop it
local moved = 0
for i = 1, 4 do vtime = vtime + 70; world.me = {x = -100 - i, y = 100 + i}; tick(1, 0); moved = moved + 1 end
-- 5 + 280s elapsed < 300 -> still running
world.last_run = nil; world.me = {x = -120, y = 120}
tick(1, 1)
assert(world.last_run and world.last_run[1] ~= false, 'transit phase still running before 300s')
world.me = {x = -130, y = 130}
tick(1, 60)                     -- now > 300s in phase 9 -> watchdog fires -> soft recovery:
                                --   Qufim IS the right conflux zone, so re-path from waypoint 1
world.last_run = nil; world.me = {x = -140, y = 140}
tick(2, 1)
assert(world.last_run and world.last_run[1] ~= false,
       'transit watchdog must soft-recover (re-path), not stop on the first trip')
print('== transit watchdog 300s soft-recovery OK ==')

cmd('stop')
print('== ALL v10.1 TESTS PASSED ==')

-- ==========================================================================
-- v10.2: MIREU / MULTI-TARGET SCENARIOS
-- ==========================================================================
local function count_engages()
    local n = 0
    for _, p in ipairs(world.injected) do
        if p.id == 0x01A and p.fields and p.fields['Category'] == 2 then n = n + 1 end
    end
    return n
end
local function count_cmd(pattern)
    local n = 0
    for _, c in ipairs(world.sent_commands or {}) do if c:find(pattern, 1, true) then n = n + 1 end end
    return n
end

-- 20. Primary boss dies, Mireu appears inside the linger window -> bot must engage Mireu,
--     NOT warp home (no 'Warp Ring' equip / phase 7).
cmd('stop')
world.bags = {[0] = {max = 2, [1] = {id = 28540, count = 1}, [2] = {id = 28541, count = 1}}}
world.zone = 288; world.player.buffs = {603}; world.player.status = 0
world.me = {x=-9.19, y=33.85}                       -- already on the arena spot
world.mobs = {[6000] = {id=6000, index=60, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=-8, y=34, distance=2}}
world.injected = {}; world.sent_commands = {}
cmd('start', 'zitah')
tick(1, 5)                                          -- arm settle window
tick(1, 5)                                          -- settled
tick(3, 1)                                          -- acquire + engage Azi Dahaka
assert(count_engages() >= 1, 'expected engage on Azi Dahaka')
world.player.status = 1
tick(2, 1)
-- boss dies
world.mobs[6000].hpp = 0
tick(1, 1)                                          -- missing_since set
tick(1, 7); tick(1, 7)                              -- >6s grace -> kill counted, /attack off
assert(count_cmd('/attack off') >= 1, 'expected disengage after kill')
world.player.status = 0
tick(1, 3)                                          -- inside 45s linger, nothing up
-- Mireu spawns 20s after the kill
world.mobs[6100] = {id=6100, index=61, name='Mireu', valid_target=true,
                    spawn_type=16, hpp=100, x=-10, y=35, distance=2}
local engages_before = count_engages()
tick(3, 10)
assert(count_engages() > engages_before, 'bot must engage Mireu that spawned inside the linger window')
assert(count_cmd('Warp Ring') == 0, 'bot must NOT warp home while Mireu is alive')
print('== Mireu spawn after primary kill -> engaged OK ==')

-- 21. Mireu dies, nothing else spawns -> after linger expires bot advances (Warp Ring phase 7).
world.player.status = 1
tick(1, 1)
world.mobs[6100].hpp = 0
tick(1, 1)
tick(1, 7); tick(1, 7)                              -- kill #2 counted
world.player.status = 0
world.sent_commands = {}
tick(1, 10)                                         -- 10s into linger: still waiting
assert(count_cmd('Warp Ring') == 0, 'must not advance before linger expires')
tick(2, 25)                                         -- ~60s > 45s linger -> arena clear -> phase 7
tick(1, 1)
assert(count_cmd('Warp Ring') >= 1, 'expected Warp Ring equip after arena clear (phase 7)')
print('== linger expiry -> advance rotation OK ==')

-- 22. Mireu is present at the same time as the boss -> sticky target (no ping-pong).
cmd('stop')
world.zone = 288; world.player.buffs = {603}; world.player.status = 0
world.me = {x=-9.19, y=33.85}
world.mobs = {[7000] = {id=7000, index=70, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=-8, y=34, distance=2},
              [7100] = {id=7100, index=71, name='Mireu', valid_target=true,
                        spawn_type=16, hpp=100, x=-40, y=60, distance=40}}
world.injected = {}
cmd('start', 'zitah')
tick(1, 5); tick(1, 5); tick(3, 1)
local first_target
for _, p in ipairs(world.injected) do
    if p.id == 0x01A and p.fields['Category'] == 2 then first_target = p.fields['Target']; break end
end
assert(first_target == 7000, 'closest target (boss) must be acquired first, got ' .. tostring(first_target))
-- Mireu moves closer; target must remain the boss (sticky)
world.mobs[7100].x, world.mobs[7100].y = -9, 34
world.player.status = 1
world.injected = {}
tick(3, 1)
for _, p in ipairs(world.injected) do
    if p.id == 0x01A and p.fields['Category'] == 2 then
        assert(p.fields['Target'] == 7000, 'target must stay sticky on the boss')
    end
end
print('== sticky target (no ping-pong) OK ==')

-- 23. Mireu-only spawn (boss not up yet) must still be engaged.
cmd('stop')
world.mobs = {[8100] = {id=8100, index=81, name='Mireu', valid_target=true,
                        spawn_type=16, hpp=100, x=-9, y=34, distance=2}}
world.player.status = 0; world.injected = {}
cmd('start', 'zitah')
tick(1, 5); tick(1, 5); tick(3, 1)
assert(count_engages() >= 1, 'Mireu alone must be engaged')
print('== Mireu-only engage OK ==')

cmd('stop')
print('== ALL v10.2 MIREU TESTS PASSED ==')


-- ==========================================================================
-- v10.5: RESILIENCE SCENARIOS
-- ==========================================================================

-- 24. THE SCREENSHOT BUG: target Reisenjima but standing in Zi'Tah with an
--     explicit 'reisenjima' arg. Old router forced phase 3 (no handler for
--     zone_index 1) -> guaranteed 300s watchdog. Now: warp home.
cmd('stop')
world.zone = 288; world.player.buffs = {}; world.mobs = {}; world.player.status = 0
world.bags = {[0] = {max = 3, [1] = {id = 28540, count = 1}, [2] = {id = 28541, count = 1}}}
world.sent_commands = {}
cmd('start', 'reisenjima')
tick(1, 5); tick(1, 5); tick(2, 1)
local warp = false
for _, c in ipairs(world.sent_commands) do if c:find('Warp Ring', 1, true) then warp = true end end
assert(warp, 'Reisenjima target while in Zi\'Tah must warp home, not sit in phase 3')
print('== zone/target mismatch escape OK ==')

-- 25. //df start with NO argument while standing in Zi'Tah adopts Zi'Tah.
cmd('stop')
world.zone = 288; world.player.buffs = {603}
world.mobs = {[5100] = {id=5100, index=61, name='Azi Dahaka', valid_target=true,
                        spawn_type=16, hpp=100, x=3, y=3, distance=9}}
world.injected = {}; world.sent_commands = {}; world.me = {x=0, y=0, z=0}
cmd('start')
tick(1, 5); tick(1, 5); tick(3, 1)
assert(count_engages() >= 1, 'no-arg start inside Zi\'Tah must adopt Zi\'Tah and fight')
for _, c in ipairs(world.sent_commands) do
    assert(not c:find('Dim. Ring', 1, true), 'must NOT try to use a Dim. Ring from inside Zi\'Tah')
end
print('== start adopts current DI zone OK ==')

-- 26. Reisenjima: no Elvorseal -> straight to Elvorseal request (phase 4), never phase 3.
cmd('stop')
world.zone = 291; world.player.buffs = {}; world.mobs = {}
world.sent_commands = {}
cmd('start', 'reisenjima')
tick(1, 5); tick(1, 5); tick(2, 1)
assert(count_cmd('sw ew domain') >= 1, 'Reisenjima without buff must request Elvorseal')
print('== Reisenjima -> Elvorseal directly OK ==')

-- 27. Stopped HUD must not keep a stale note; //df resume restarts cleanly.
cmd('stop')
world.zone = 245; world.bags = {[0] = {max = 2, [1] = {id = 1, count = 1}}}   -- no rings -> stop
cmd('start', 'reisenjima'); tick(3)
world.bags = {[0] = {max = 3, [1] = {id = 28540, count = 1}, [2] = {id = 28541, count = 1}}}
world.sent_commands = {}
cmd('resume'); tick(2)
local saw_equip2 = false
for _, c in ipairs(world.sent_commands) do if c:find('/equip', 1, true) then saw_equip2 = true end end
assert(saw_equip2, '//df resume must restart travel for the current target')
print('== resume OK ==')

-- 28. Unrecognized zone: after the grace period the bot warps home instead of idling.
cmd('stop')
world.zone = 999; zones[999] = {id=999, en='Mystery Zone', name='Mystery Zone'}
world.sent_commands = {}
cmd('start', 'reisenjima')
tick(1, 5); tick(1, 5); tick(1, 40); tick(2, 1)
local warp2 = false
for _, c in ipairs(world.sent_commands) do if c:find('Warp Ring', 1, true) then warp2 = true end end
assert(warp2, 'unrecognized zone must fall back to the Warp Ring after the grace period')
print('== unknown zone escape OK ==')

cmd('stop')
print('== ALL v10.5 RESILIENCE TESTS PASSED ==')

-- 13. stop resets cleanly
cmd('stop'); cmd('status')
events['unload']()
print('== ALL SMOKE TESTS PASSED ==')
