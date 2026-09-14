--[[
    libs/df_zones.lua

    Zone ID resolution and the Domain Invasion rotation table. All routing
    elsewhere in DomainFarm is by zone ID (resolved here, once, at load),
    never by name-string comparison at runtime.

    Returns a table:
        ZONES             -- { reisenjima=id, zitah=id, ruaun=id, qufim=id, ... }
        safe_zone_ids      -- set of town/home-point zone IDs
        portal_zone_ids    -- set of crag zone IDs (La Theine/Konschtat/Tahrongi)
        conflux_zone_ids   -- set of conflux zone IDs (Qufim/Misareaux)
        rotation           -- { [1..3] = {label, zone, boss, targets} } (no
                              `arena` field yet -- DomainFarm.lua attaches that
                              after also loading libs/df_waypoints)
        zone_name_of(id)   -- helper
]]

local res = require('resources')

local function zone_id_of(name)
    local z = res.zones:with('en', name)
    if not z then
        warning(('Zone "%s" not found in resources; routing for it is disabled.'):format(name))
        return nil
    end
    return z.id
end

local function zone_name_of(id)
    local z = id and res.zones[id]
    return z and z.name or ('Zone #' .. tostring(id or '?'))
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
    -- Added after a //df start defaulted to the Warp Ring for a zone that
    -- wasn't in this hand-typed list -- if that still happens, the "not in
    -- safe_zone_names" warning now names the exact missing zone.
    'Aht Urhgan Whitegate', 'Nashmau', 'Tavnazian Safehold', 'Al Zahbi',
}
local safe_zone_ids = {}
for _, name in ipairs(safe_zone_names) do
    local id = zone_id_of(name)
    if id then safe_zone_ids[id] = true end
end

-- Crag-teleport zones (where the Dimensional Portal to Reisenjima stands).
local portal_zone_ids = {}
for _, key in ipairs({'la_theine', 'konschtat', 'tahrongi'}) do
    if ZONES[key] then portal_zone_ids[ZONES[key]] = true end
end

-- Conflux tunnel zones.
local conflux_zone_ids = {}
if ZONES.qufim     then conflux_zone_ids[ZONES.qufim]     = true end
if ZONES.misareaux then conflux_zone_ids[ZONES.misareaux] = true end

-- 1: Reisenjima (Quetzalcoatl), 2: Escha-Zi'Tah (Azi Dahaka), 3: Escha-Ru'Aun (Naga Raja).
local rotation = {
    [1] = {label = 'Reisenjima (Quetzalcoatl)',   zone = ZONES.reisenjima, boss = 'Quetzalcoatl'},
    [2] = {label = "Escha - Zi'Tah (Azi Dahaka)", zone = ZONES.zitah,      boss = 'Azi Dahaka'},
    [3] = {label = "Escha - Ru'Aun (Naga Raja)",  zone = ZONES.ruaun,      boss = 'Naga Raja'},
}

return {
    ZONES            = ZONES,
    safe_zone_ids    = safe_zone_ids,
    portal_zone_ids  = portal_zone_ids,
    conflux_zone_ids = conflux_zone_ids,
    rotation         = rotation,
    zone_id_of       = zone_id_of,
    zone_name_of     = zone_name_of,
}
