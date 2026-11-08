local ADDON_NAME, NS = ...

-- Tracked tank abilities per class (from TankAlertForever Data/SpellData.lua). Keyed by display name; detection
-- matches the spell ID first, then the name. isTaunt: always announced, even while threat is solid.
-- Spell IDs are Vanilla's; not all are confirmed on the Forever build yet (kb/addons/TankAlert.md).
-- Earthshaker Slam and Lightning Strike are Turtle-only names (no IDs): matched by name if they ever exist.
local Spells = {}
NS.AlertSpells = Spells

Spells.Abilities = {
    WARRIOR = {
        ["Taunt"]        = { spellIDs = { 355 }, isTaunt = true },
        ["Mocking Blow"] = { spellIDs = { 694, 7400, 7402, 20559, 20560, 25266 }, isTaunt = true },
        ["Sunder Armor"] = { spellIDs = { 7386, 7405, 8380, 11596, 11597, 25225 } },
        ["Revenge"]      = { spellIDs = { 6572, 6574, 7379, 11600, 11601, 25288 } },
        ["Shield Slam"]  = { spellIDs = { 23922, 23923, 23924, 23925, 25258 } },
    },
    DRUID = {
        ["Growl"] = { spellIDs = { 6795 }, isTaunt = true },
    },
    PALADIN = {
        ["Hand of Reckoning"] = { spellIDs = { 62124 }, isTaunt = true },
        ["Righteous Defense"] = { spellIDs = { 31789 }, isTaunt = true },
        ["Holy Strike"]       = { spellIDs = { 46399, 46400, 46401 } },
    },
    SHAMAN = {
        ["Earthshaker Slam"] = { spellIDs = {}, isTaunt = true },
        ["Earth Shock"]      = { spellIDs = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } },
        ["Frost Shock"]      = { spellIDs = { 8056, 8058, 10472, 10473 } },
        ["Lightning Strike"] = { spellIDs = {} },
        ["Stormstrike"]      = { spellIDs = { 17364 } },
    },
}

-- Display order on the Abilities page.
Spells.Order = {
    WARRIOR = { "Taunt", "Mocking Blow", "Sunder Armor", "Revenge", "Shield Slam" },
    DRUID = { "Growl" },
    PALADIN = { "Hand of Reckoning", "Righteous Defense", "Holy Strike" },
    SHAMAN = { "Earthshaker Slam", "Earth Shock", "Frost Shock", "Lightning Strike", "Stormstrike" },
}

local byName, byID = {}, {}
for class, abilities in pairs(Spells.Abilities) do
    byName[class], byID[class] = {}, {}
    for name, data in pairs(abilities) do
        byName[class][name:lower()] = name
        for _, id in ipairs(data.spellIDs) do byID[class][id] = name end
    end
end

-- Ability name for a cast (spell ID first, then the spell name), or nil when it isn't tracked for the class.
function Spells.Find(class, spellID, spellName)
    if not class or not byID[class] then return nil end
    local id = NS.Utils.SafeNumber(spellID)
    if id and byID[class][id] then return byID[class][id] end
    local name = NS.Utils.SafeString(spellName, nil)
    if name and name ~= "" then return byName[class][name:lower()] end
    return nil
end

function Spells.Get(class, name)
    return Spells.Abilities[class] and Spells.Abilities[class][name]
end
