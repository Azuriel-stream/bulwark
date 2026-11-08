local ADDON_NAME, NS = ...

-- Shared secret-safe helpers. One copy for every area; the areas' own helpers join here when they're ported
-- (merged from TankAlertForever/TankAuditForever/TankMarkForever Core/Utils.lua).
local Utils = {}
NS.Utils = Utils

---------------------------------------------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------------------------------------------

-- True when the value is a secret (restricted in combat/instances, kb/restrictions.md).
function Utils.IsSecret(val)
    if val == nil then return false end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, val)
        if ok then return secret == true end
    end
    -- Fallback: secrets refuse comparison and concatenation.
    if not pcall(function() return val == "" end) then return true end
    if not pcall(function() return val .. "" end) then return true end
    return false
end

-- The value as a plain string, or fallback when it's nil, secret or not convertible.
function Utils.SafeString(val, fallback)
    if val == nil or Utils.IsSecret(val) then return fallback end
    if type(val) == "string" then return val end
    local ok, str = pcall(tostring, val)
    if ok and type(str) == "string" and not Utils.IsSecret(str) then return str end
    return fallback
end

-- A plain number, or fallback when it's nil, secret or not a number.
function Utils.SafeNumber(val, fallback)
    if type(val) ~= "number" or Utils.IsSecret(val) then return fallback end
    return val
end

---------------------------------------------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------------------------------------------

-- "RAID", "PARTY" or "SOLO".
function Utils.GetGroupType()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return "SOLO"
end

-- Raid leader or assistant (only in a raid; Raid Warning needs it).
function Utils.IsRaidLeaderOrAssist()
    if not (IsInRaid and IsInRaid()) then return false end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
    return false
end

---------------------------------------------------------------------------------------------------------------
-- Unit names (Forever characters have surnames: "First Last")
---------------------------------------------------------------------------------------------------------------

local scanTooltip
-- First tooltip line for the unit: a fallback when UnitName is secret.
local function TooltipUnitName(unit)
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "Bulwark_ScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTooltip:ClearLines()
    if not pcall(scanTooltip.SetUnit, scanTooltip, unit) then return nil end
    local line1 = _G["Bulwark_ScanTooltipTextLeft1"]
    local text = line1 and line1.GetText and line1:GetText()
    text = Utils.SafeString(text, nil)
    if text and text ~= "" and text:lower() ~= "target" then return text end
    return nil
end

-- Full character name ("First Last"), or nil when the unit doesn't exist or the name is unreadable.
function Utils.GetUnitFullName(unit)
    if not unit then return nil end
    local okExists, exists = pcall(UnitExists, unit)
    if (not okExists or not exists) and unit ~= "player" then return nil end

    local rawName, rawSurname
    if not pcall(function() rawName, rawSurname = UnitName(unit) end) then return nil end
    local name = Utils.SafeString(rawName, nil)
    local surname = Utils.SafeString(rawSurname, nil)
    if name and name ~= "" and surname and surname ~= "" then
        return name .. " " .. surname
    end

    if GetUnitName then
        pcall(function()
            local full = Utils.SafeString(GetUnitName(unit, true), nil)
            if full and full ~= "" then
                name = full:gsub("-", " ")
            end
        end)
    end

    if not name or name == "" or name:lower() == "target" then
        name = TooltipUnitName(unit) or name
    end
    return name
end

-- Unit name that is never secret: the full name, else the plain name, else fallback.
function Utils.GetSafeUnitName(unit, fallback)
    if not unit then return fallback end
    local ok, full = pcall(Utils.GetUnitFullName, unit)
    local name = ok and Utils.SafeString(full, nil) or nil
    if not name or name == "" or (name:lower() == "target" and unit ~= "target") then
        local okRaw, raw = pcall(UnitName, unit)
        local safe = okRaw and Utils.SafeString(raw, nil)
        if safe and safe ~= "" then name = safe end
    end
    if name and name ~= "" and name:lower() ~= "target" then return name end
    return fallback
end

---------------------------------------------------------------------------------------------------------------
-- Raid target icons
---------------------------------------------------------------------------------------------------------------

local ICON_PATH = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:0|t"
local TOKEN_ICONS = {
    ["{rt1}"] = 1, ["{rt2}"] = 2, ["{rt3}"] = 3, ["{rt4}"] = 4, ["{rt5}"] = 5, ["{rt6}"] = 6, ["{rt7}"] = 7, ["{rt8}"] = 8,
    ["{star}"] = 1, ["{circle}"] = 2, ["{coin}"] = 2, ["{diamond}"] = 3, ["{triangle}"] = 4, ["{moon}"] = 5,
    ["{square}"] = 6, ["{cross}"] = 7, ["{x}"] = 7, ["{skull}"] = 8,
}

-- Chat tokens ({rt1}, {skull}...) as inline textures, for local output. Plain gsub on purpose:
-- C_ChatInfo.ReplaceIconAndGroupExpressions is suspected of taint in combat paths (kb/gotchas.md).
function Utils.ReplaceRaidTokens(text)
    if not text or text == "" then return text end
    return (text:gsub("{%a+%d?}", function(token)
        local index = TOKEN_ICONS[token:lower()]
        return index and string.format(ICON_PATH, index) or token
    end))
end

-- Icon index (1-8) read from the target/focus frame or the unit's nameplate texture coordinates
-- (GetRaidTargetIndex is secret in restricted states, the frames' textures are not).
local function IconFromFrame(unit)
    local texture
    if unit == "target" or unit == "focus" then
        local uf = unit == "target" and TargetFrame or FocusFrame
        local content = uf and uf.TargetFrameContent and uf.TargetFrameContent.TargetFrameContentContextual
        texture = (content and content.RaidTargetIcon) or _G[(unit == "target" and "TargetFrame" or "FocusFrame") .. "RaidTargetIcon"]
    end
    if not texture and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and plate and plate.UnitFrame and plate.UnitFrame.RaidTargetFrame then
            texture = plate.UnitFrame.RaidTargetFrame.RaidTargetIcon
        end
    end
    if not texture then return nil end
    local okShown, shown = pcall(texture.IsShown, texture)
    if not okShown or not shown then return nil end
    local okCoord, ulx, uly = pcall(texture.GetTexCoord, texture)
    if not okCoord or Utils.SafeNumber(ulx) == nil or Utils.SafeNumber(uly) == nil then return nil end
    local index = math.floor(uly * 4 + 0.5) * 4 + math.floor(ulx * 4 + 0.5) + 1
    if index >= 1 and index <= 8 then return index end
    return nil
end

-- Icons the player set (SetRaidTarget hook), by name and GUID: readable even when the API is secret.
local markedByPlayer = {}
local function OnSetRaidTarget(unit, index)
    if not unit or Utils.SafeNumber(index) == nil then return end
    local name = Utils.SafeString(UnitName(unit), nil)
    local guid = Utils.SafeString(UnitGUID(unit), nil)
    local value = (index >= 1 and index <= 8) and index or nil
    if name then markedByPlayer[name] = value end
    if guid then markedByPlayer[guid] = value end
end
if hooksecurefunc and SetRaidTarget then
    pcall(hooksecurefunc, "SetRaidTarget", OnSetRaidTarget)
end

-- Raid icon index (1-8) on the unit, or nil.
function Utils.GetRaidTargetIndex(unit)
    if not unit then return nil end
    local guid = Utils.SafeString(UnitGUID(unit), nil)
    if guid and markedByPlayer[guid] then return markedByPlayer[guid] end
    local name = Utils.SafeString(UnitName(unit), nil)
    if name and markedByPlayer[name] then return markedByPlayer[name] end
    local fromFrame = IconFromFrame(unit)
    if fromFrame then return fromFrame end
    local ok, index = pcall(GetRaidTargetIndex, unit)
    index = ok and Utils.SafeNumber(index) or nil
    if index and index >= 1 and index <= 8 then return index end
    return nil
end

-- "{rtN}" for the unit's icon, falling back to target, mouseover and focus; "" when none.
function Utils.GetRaidTargetToken(unit)
    local index = Utils.GetRaidTargetIndex(unit)
    for _, other in ipairs({ "target", "mouseover", "focus" }) do
        if index then break end
        if other ~= unit then index = Utils.GetRaidTargetIndex(other) end
    end
    return index and ("{rt" .. index .. "}") or ""
end
