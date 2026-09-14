--[[
    libs/df_waypoints.lua

    Static waypoint data for DomainFarm.

    v11 replaced the dynamic-approach NPCs' fixed paths with a straight-line
    walk to the live entity (see DomainFarm.lua's header). That was wrong to
    do unconditionally: those paths exist to route around real terrain (a
    wall, a ledge) between the zone entrance and the NPC, not just to land
    within Superwarp's interact range -- a straight vector into a wall
    doesn't get corrected by knowing the NPC's exact live position, it just
    walks into the wall and sits there. v11.1 restores them as a first
    stage: walk the known-good path, THEN do the dynamic find-and-interact
    for the last stretch (which is still a real improvement over the old
    "blind Superwarp command" -- it's what fixed the original "too far / no
    eschan npcs found" crash).
]]

return {
    -- Zone-entrance -> Domain Invasion NPC (phase 3, terrain-following).
    zitah_waypoints = { {x = -345.43, y = -178.93}, {x = -349.69, y = -175.19}, {x = -353.34, y = -171.91}, {x = -355.45, y = -171.26} },
    ruaun_waypoints = { {x =   -0.37, y = -466.98}, {x =   -4.43, y = -463.94}, {x =   -9.29, y = -460.63} },

    -- Zone-entrance -> Undulating Confluence (phase 9, terrain-following).
    q_waypoints = { {x = -212.00, y =  94.00}, {x = -207.61, y =  88.76}, {x = -203.64, y =  84.19}, {x = -201.26, y =  81.52}, {x = -203.09, y =  77.94} },
    m_waypoints = { {x =  -66.00, y = 562.00}, {x =  -65.22, y = 565.10}, {x =  -63.39, y = 568.49}, {x =  -60.10, y = 570.39}, {x = -56.77, y = 569.21}, {x = -52.69, y = 567.83}, {x = -50.37, y = 567.07}, {x = -49.57, y = 570.27} },

    -- Post-teleport landing spot -> boss engagement point (phase 6).
    zitah_arena_wps = { {x =  -6.77, y =  52.33}, {x =  -7.74, y =  44.74}, {x =  -8.40, y =  39.76}, {x =  -9.19, y =  33.85} },
    ruaun_arena_wps = { {x =   2.25, y = -223.03}, {x =   5.04, y = -217.67}, {x =   6.67, y = -212.86}, {x =   8.38, y = -211.61} },
    reisen_arena    = {x = 612.17, y = -933.43},
}
