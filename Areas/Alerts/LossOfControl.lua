local ADDON_NAME, NS = ...
local L, Utils = NS.L, NS.Utils

-- Stunned / feared / incapacitated / disarmed (from TankAlertForever Modules/LossOfControl.lua).
-- LOSS_OF_CONTROL_ADDED/UPDATE first; UI_ERROR_MESSAGE ("Can't do that while stunned") as a fallback.
local LossOfControl = NS:RegisterModule("LossOfControl", "alerts")
local frame = CreateFrame("Frame", "Bulwark_LossOfControlFrame")

local active = {}   -- [STUNNED|FEARED|INCAPACITATED|DISARMED] = true while it lasts

-- Known CC spells by lower-case name, for LOC entries without a usable locType.
local CC_SPELLS = {
    ["hammer of justice"] = "STUNNED", ["kidney shot"] = "STUNNED", ["cheap shot"] = "STUNNED", ["bash"] = "STUNNED",
    ["intercept stun"] = "STUNNED", ["concussion blow"] = "STUNNED", ["charge stun"] = "STUNNED",
    ["war stomp"] = "STUNNED", ["pounce"] = "STUNNED", ["impact"] = "STUNNED", ["blackout"] = "STUNNED",
    ["tidal charm"] = "STUNNED", ["pyroclasm"] = "STUNNED", ["mace stun effect"] = "STUNNED", ["revenge stun"] = "STUNNED",
    ["psychic scream"] = "FEARED", ["howl of terror"] = "FEARED", ["fear"] = "FEARED", ["intimidating shout"] = "FEARED",
    ["scare beast"] = "FEARED", ["seduction"] = "FEARED", ["terrify"] = "FEARED", ["panic"] = "FEARED",
    ["bellowing roar"] = "FEARED", ["frightening shout"] = "FEARED",
    ["polymorph"] = "INCAPACITATED", ["polymorph: pig"] = "INCAPACITATED", ["polymorph: turtle"] = "INCAPACITATED",
    ["sap"] = "INCAPACITATED", ["gouge"] = "INCAPACITATED", ["blind"] = "INCAPACITATED",
    ["freezing trap"] = "INCAPACITATED", ["freezing trap effect"] = "INCAPACITATED", ["repentance"] = "INCAPACITATED",
    ["sleep"] = "INCAPACITATED", ["wyvern sting"] = "INCAPACITATED", ["scatter shot"] = "INCAPACITATED",
    ["reckless charge"] = "INCAPACITATED", ["hibernate"] = "INCAPACITATED", ["shackle undead"] = "INCAPACITATED",
    ["disarm"] = "DISARMED", ["riposte"] = "DISARMED",
}

local LOC_TYPES = {
    STUN = "STUNNED", STUN_MECHANIC = "STUNNED",
    FEAR = "FEARED", FEAR_MECHANIC = "FEARED", CHARM = "FEARED",
    CONFUSE = "INCAPACITATED", INCAPACITATE = "INCAPACITATED", SLEEP = "INCAPACITATED", PACIFY = "INCAPACITATED",
    DISARM = "DISARMED",
}

local function HasMainHandWeapon()
    local ok, link = pcall(GetInventoryItemLink, "player", 16)
    return ok and link ~= nil
end

-- Bear or Dire Bear Form (druids only announce while tanking).
local function InBearForm()
    if GetShapeshiftFormID then
        local ok, form = pcall(GetShapeshiftFormID)
        form = ok and Utils.SafeNumber(form)
        if form == 1 or form == 5 then return true end
    end
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        local okNum, count = pcall(GetNumShapeshiftForms)
        for i = 1, (okNum and Utils.SafeNumber(count, 0) or 0) do
            local ok, _, isActive, _, spellID = pcall(GetShapeshiftFormInfo, i)
            if ok and isActive == true and (spellID == 5487 or spellID == 9634) then return true end
        end
    end
    return false
end

local function Trigger(kind)
    if active[kind] then return end
    active[kind] = true
    if NS.playerClass == "DRUID" and not InBearForm() then return end
    local target = Utils.GetSafeUnitName("target", nil)
    local icon = Utils.GetRaidTargetToken("target")
    if kind == "DISARMED" then
        NS.AlertsAnnouncer:DisarmAlert(target, icon)
    else
        NS.AlertsAnnouncer:LossOfControlAlert(kind, target, icon)
    end
end

local function KindFromName(name)
    local lower = name:lower()
    if CC_SPELLS[lower] then return CC_SPELLS[lower] end
    if lower:find("stun") then return "STUNNED" end
    if lower:find("fear") or lower:find("flee") then return "FEARED" end
    if lower:find("incapacitat") or lower:find("sleep") then return "INCAPACITATED" end
    if lower:find("disarm") then return "DISARMED" end
    return nil
end

local function OnLossOfControlAdded(index)
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData) then return end
    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlData, index)
    if not ok or type(data) ~= "table" then return end
    -- Since build 70888 this data is always secret (SecretWhenLossOfControlRestricted) [docs]. Read the fields under
    -- pcall in case the table itself is secret; secret fields come back as "" / nil and the UI-error path takes over.
    local okRead, locType, locName, locSpell = pcall(function() return data.locType, data.name, data.spellID end)
    if not okRead then return end
    local kind = LOC_TYPES[Utils.SafeString(locType, "")]
    if not kind then
        local name = Utils.SafeString(locName, "")
        if name == "" then
            local id = Utils.SafeNumber(locSpell)
            local okName, spell = pcall(C_Spell.GetSpellName, id)
            name = okName and Utils.SafeString(spell, "") or ""
        end
        kind = name ~= "" and KindFromName(name) or nil
    end
    if kind then Trigger(kind) end
end

local function OnLossOfControlUpdate()
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then return end
    local ok, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCount)
    if ok and Utils.SafeNumber(count) == 0 then wipe(active) end
end

local function OnUIError(_, message)
    local lower = Utils.SafeString(message, ""):lower()
    if lower == "" then return end
    if lower:find("while stunned") or lower:find("you are stunned") then
        Trigger("STUNNED")
    elseif lower:find("while feared") or lower:find("while fleeing") or lower:find("you are fleeing") then
        Trigger("FEARED")
    elseif lower:find("while incapacitated") or lower:find("while confused") or lower:find("while asleep")
        or lower:find("you are incapacitated") then
        Trigger("INCAPACITATED")
    elseif lower:find("must have a melee weapon equipped in the main hand") or lower:find("while disarmed")
        or lower:find("you are disarmed") then
        if HasMainHandWeapon() then Trigger("DISARMED") end
    end
end

local function OnEvent(_, event, ...)
    if event == "LOSS_OF_CONTROL_ADDED" then
        -- Payload (unitTarget, effectIndex) [docs]. TankAlertForever passed the unit as the index, so its
        -- LOC path never fired and only the UI-error fallback worked.
        local unit, index = ...
        if unit == "player" then OnLossOfControlAdded(index) end
    elseif event == "LOSS_OF_CONTROL_UPDATE" then
        if ... == "player" then OnLossOfControlUpdate() end
    elseif event == "UI_ERROR_MESSAGE" then
        OnUIError(...)
    end
end

function LossOfControl:OnEnable()
    pcall(frame.RegisterEvent, frame, "LOSS_OF_CONTROL_ADDED")
    pcall(frame.RegisterEvent, frame, "LOSS_OF_CONTROL_UPDATE")
    frame:RegisterEvent("UI_ERROR_MESSAGE")
    frame:SetScript("OnEvent", OnEvent)
end

function LossOfControl:OnDisable()
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    wipe(active)
end

-- /bwk alerts test cc|disarm
function LossOfControl:Simulate(kind)
    active[kind] = nil
    Trigger(kind)
    active[kind] = nil
end
