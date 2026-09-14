--[[
    libs/df_trusts.lua

    Trust lineup and the "what should I summon next" lookup. Pure function of
    the live party/spell state -- no DomainFarm state.* touched here, so this
    has no dependency on the main script beyond the 'resources' library.
]]

local res = require('resources')

local trust_list = {
    {spell = 'Ulmia',       alt = 'Arciela II'},
    {spell = 'Qultada',     alt = nil},
    {spell = 'Koru-Moru',   alt = nil},
    {spell = 'Joachim',     alt = 'Lilisette'},
    {spell = 'Sylvie (UC)', alt = 'Prishe II'},
}

-- Returns the name of the next trust spell to cast, or nil if the party is
-- full or every trust we know is already out / on recast.
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

return {
    trust_list       = trust_list,
    get_missing_trust = get_missing_trust,
}
