local ADDON_NAME, NS = ...

-- Tracked tank abilities per class. Keyed by display name; detection matches the spell ID first, then the name.
-- isTaunt: always announced, even while threat is solid. tauntWithSeal: a taunt only while that seal is up
-- (AbilityAlerts tracks the seal), otherwise a normal threat ability.
-- Only abilities that exist on Forever (user, 2026-11-13). IDs checked with tools/gamedata.ps1, build 70938:
-- Hand of Reckoning / Righteous Defense (TBC+) and the Turtle-only Earthshaker Slam / Lightning Strike are gone.
-- Paladin facts: kb/tanks/paladin.md.
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
        -- Forever's Paladin taunt: Judgement while Seal of Fury is up (Judgement of Fury, taunt effect 20232).
        -- Judgement doesn't consume the seal [data: 20271].
        ["Judgement"]   = { spellIDs = { 20271 }, tauntWithSeal = "FURY" },
        ["Holy Strike"] = { spellIDs = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 } },
    },
    SHAMAN = {
        ["Earth Shock"] = { spellIDs = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } },
        ["Frost Shock"] = { spellIDs = { 8056, 8058, 10472, 10473 } },
        ["Stormstrike"] = { spellIDs = { 17364 } },
    },
}

-- Paladin seals (every rank, [data] build 70938), for tauntWithSeal. Casting another seal replaces the active one.
Spells.SEALS = {
    FURY = { 20163, 20419, 20421, 20422, 20423, 1311649, 1311656 },
    OTHER = {
        20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293,   -- Seal of Righteousness
        21082, 20162, 20305, 20306, 20307, 20308,                 -- Seal of the Crusader
        20164,                                                    -- Seal of Justice
        20165, 20347, 20348, 20349,                               -- Seal of Light
        20166, 20356, 20357,                                      -- Seal of Wisdom
        20375, 20915, 20918, 20919, 20920,                        -- Seal of Command
    },
}
Spells.SEAL_DURATION = 30

-- Display order on the Abilities page.
Spells.Order = {
    WARRIOR = { "Taunt", "Mocking Blow", "Sunder Armor", "Revenge", "Shield Slam" },
    DRUID = { "Growl" },
    PALADIN = { "Judgement", "Holy Strike" },
    SHAMAN = { "Earth Shock", "Frost Shock", "Stormstrike" },
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
