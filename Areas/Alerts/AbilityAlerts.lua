local ADDON_NAME, NS = ...
local L, Utils, Spells = NS.L, NS.Utils, NS.AlertSpells

-- Failed taunts and threat abilities (from TankAlertForever Modules/AbilityAlerts.lua).
-- Forever: the combat log is forbidden (kb/gotchas.md#cleu). Instead: UNIT_SPELLCAST_SENT remembers the cast,
-- then UNIT_COMBAT on target/focus/mouseover within 1.5 s says whether it missed/dodged/parried..., and
-- UI_ERROR_MESSAGE catches immune / out of range / interrupted.
local AbilityAlerts = NS:RegisterModule("AbilityAlerts", "alerts")
local frame = CreateFrame("Frame", "Bulwark_AbilityAlertsFrame")

local CAST_WINDOW = 1.5
local cast = nil   -- { ability, isTaunt, target, icon, time }

-- Paladin seals (tauntWithSeal): which seal the player cast last and when it runs out. Auras are secret in combat
-- (kb/restrictions.md), so the seal is tracked from the player's own casts; out of combat the aura check also works
-- (e.g. a seal cast before a /reload). Unknown seal = Judgement counts as a normal threat ability.
local SEAL_OF = {}
for kind, ids in pairs(Spells.SEALS) do for _, id in ipairs(ids) do SEAL_OF[id] = kind end end
local seal = { kind = nil, untilTime = 0 }

local MISS_TYPES = {
    MISS = "MISSED", DODGE = "DODGED", PARRY = "PARRIED", BLOCK = "BLOCKED", RESIST = "RESISTED",
    IMMUNE = "IMMUNE", DEFLECT = "DEFLECTED", REFLECT = "REFLECTED", EVADE = "EVADED",
}

local function cfg() return NS.db.alerts end

function AbilityAlerts.IsTracked(class, ability)
    local saved = cfg().abilities[class]
    if saved and saved[ability] ~= nil then return saved[ability] end
    return Spells.Get(class, ability) ~= nil
end

function AbilityAlerts.SetTracked(class, ability, on)
    cfg().abilities[class] = cfg().abilities[class] or {}
    cfg().abilities[class][ability] = on and true or false
end

-- Solid threat: top of the mob's list and well ahead of second place (lead state 0 of 0-3).
-- UnitThreatLeadSituation is SecretWhenUnitThreatStateRestricted; player vs target reads fine in combat
-- [in-game]. Unknown (nil or secret) counts as not solid, so the alert still goes out.
local function HasSolidThreat(unit)
    if not UnitThreatLeadSituation then return false end
    local ok, lead = pcall(UnitThreatLeadSituation, "player", unit)
    return ok and Utils.SafeNumber(lead) == 0
end

-- Taunts always announce; other abilities stay quiet while threat is solid (option quietWhenThreatSolid).
local function QuietForThreat(unit, failure)
    if cast.isTaunt or not cfg().quietWhenThreatSolid then return false end
    if not HasSolidThreat(unit) then return false end
    NS:Debug(L["DEBUG_QUIET_THREAT"], cast.ability, failure)
    return true
end

local function SpellName(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellName) then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    return ok and Utils.SafeString(name, nil) or nil
end

local function HasSealAura(kind)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    for _, id in ipairs(Spells.SEALS[kind] or {}) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and aura ~= nil then return true end
    end
    return false
end

function AbilityAlerts.SealActive(kind)
    if seal.kind == kind and GetTime() < seal.untilTime then return true end
    return HasSealAura(kind)
end

local function OnSpellcastSucceeded(unit, _, spellID)
    if unit ~= "player" then return end
    local kind = SEAL_OF[Utils.SafeNumber(spellID) or 0]
    if kind then
        seal.kind, seal.untilTime = kind, GetTime() + Spells.SEAL_DURATION
    end
end

local function OnSpellcastSent(unit, target, _, spellID)
    if unit ~= "player" then return end
    spellID = Utils.SafeNumber(spellID)
    local spellName = SpellName(spellID)
    local ability = Spells.Find(NS.playerClass, spellID, spellName)
    if not ability or not AbilityAlerts.IsTracked(NS.playerClass, ability) then return end

    -- The target name from the event, else the target's name; drop realm suffixes.
    local name = Utils.SafeString(target, nil)
    if not name or name == "" or name == spellName or name:lower() == "target" then
        name = Utils.GetSafeUnitName("target", nil)
    end
    if name then name = name:match("^([^-]+)") or name end

    local icon = Utils.GetRaidTargetToken("target")
    local data = Spells.Get(NS.playerClass, ability)
    local isTaunt = data.isTaunt == true or (data.tauntWithSeal ~= nil and AbilityAlerts.SealActive(data.tauntWithSeal))
    cast = { ability = ability, isTaunt = isTaunt, target = name, icon = icon, time = GetTime() }
end

local function Expired()
    if cast and GetTime() - cast.time > CAST_WINDOW then cast = nil end
    return cast == nil
end

local function OnUnitCombat(unit, action)
    if unit ~= "target" and unit ~= "focus" and unit ~= "mouseover" then return end
    if Expired() then return end
    action = Utils.SafeString(action, "")
    if action == "WOUND" or action == "DAMAGE" then   -- it hit
        cast = nil
        return
    end
    local failure = MISS_TYPES[action]
    if not failure then return end
    if not QuietForThreat(unit, failure) then
        local target = cast.target or Utils.GetSafeUnitName(unit, nil) or Utils.GetSafeUnitName("target", L["TARGET"])
        local icon = Utils.GetRaidTargetIndex(unit) and Utils.GetRaidTargetToken(unit) or cast.icon
        NS.AlertsAnnouncer:AbilityAlert(cast.ability, failure, target, icon)
    end
    cast = nil
end

local function OnUIError(errorType, message)
    if Expired() then return end
    local text = Utils.SafeString(message, "") ~= "" and Utils.SafeString(message, "") or Utils.SafeString(errorType, "")
    local lower = text:lower()
    local failure
    if lower:find("immune") then
        failure = "IMMUNE"
    elseif lower:find("too close") or lower:find("out of range") then
        failure = "OUT_OF_RANGE"
    elseif lower:find("interrupted") then
        failure = "INTERRUPTED"
    end
    if not failure then return end
    if not QuietForThreat("target", failure) then
        local icon = cast.icon ~= "" and cast.icon or Utils.GetRaidTargetToken("target")
        NS.AlertsAnnouncer:AbilityAlert(cast.ability, failure, cast.target, icon)
    end
    cast = nil
end

local function OnEvent(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        OnSpellcastSent(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellcastSucceeded(...)
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "UI_ERROR_MESSAGE" then
        OnUIError(...)
    end
end

function AbilityAlerts:OnEnable()
    frame:RegisterEvent("UNIT_SPELLCAST_SENT")
    if NS.playerClass == "PALADIN" then frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end
    frame:RegisterEvent("UNIT_COMBAT")
    frame:RegisterEvent("UI_ERROR_MESSAGE")
    frame:SetScript("OnEvent", OnEvent)
end

function AbilityAlerts:OnDisable()
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    cast = nil
end

-- /bwk alerts test miss: the real alert path with the class's first ability.
function AbilityAlerts:Simulate()
    local order = Spells.Order[NS.playerClass]
    local ability = order and order[1] or "Taunt"
    local target = Utils.GetSafeUnitName("target", L["TEST_DUMMY"])
    local icon = Utils.GetRaidTargetToken("target")
    NS.AlertsAnnouncer:AbilityAlert(ability, "RESISTED", target, icon ~= "" and icon or "{rt8}")
end
