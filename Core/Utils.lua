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

-- Set from a list ({ 1, 2 } -> { [1] = true, [2] = true }).
function Utils.ToSet(list)
    local set = {}
    for _, v in ipairs(list or {}) do set[v] = true end
    return set
end

-- "2h", "5m", "40s".
function Utils.FormatTime(seconds)
    if seconds >= 3600 then return math.ceil(seconds / 3600) .. "h" end
    if seconds > 60 then return math.ceil(seconds / 60) .. "m" end
    return tostring(math.max(0, math.ceil(seconds))) .. "s"
end

---------------------------------------------------------------------------------------------------------------
-- Spells and auras
---------------------------------------------------------------------------------------------------------------

-- Off-hand item is a shield (Armor class 4, subclass 6). GetBlockChance() doesn't tell: it reports the full block
-- chance with no shield worn [in-game 2026-11-12].
function Utils.HasShield()
    local ok, link = pcall(GetInventoryItemLink, "player", 17)
    if not ok or type(link) ~= "string" then return false end
    local okInfo, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, link)
    return okInfo and classID == 4 and subClassID == 6
end

-- Forever: the global IsPlayerSpell is only a deprecation shim (kb/gotchas.md#deprecation-fallbacks).
function Utils.IsKnown(spellID)
    return spellID ~= nil and C_SpellBook.IsSpellKnown(spellID) == true
end

-- True if the player knows any rank.
function Utils.KnowsAny(ids)
    for _, id in ipairs(ids or {}) do
        if Utils.IsKnown(id) then return true end
    end
    return false
end

function Utils.SpellName(id)
    return id and C_Spell.GetSpellName(id) or nil
end

-- Spell name as plain "[Name]" for chat. Never a spell link: a ranked link corrupts the text after it in a sent
-- message, for every reader [in-game] (kb/gotchas.md#spell-link-chat).
function Utils.SpellChatName(id, fallbackName)
    local name = id and C_Spell.GetSpellName(id)
    if not name or Utils.IsSecret(name) or name == "" then name = fallbackName or "?" end
    return "[" .. name .. "]"
end

-- Calls callback(aura) for each of the unit's auras (filter "HELPFUL"/"HARMFUL"). Returns false, and stops, as soon
-- as the data is secret (restricted: combat, encounters).
function Utils.ForEachAura(unit, filter, callback)
    for index = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not aura then return true end
        if Utils.IsSecret(aura.spellId) then return false end
        callback(aura)
    end
    return true
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

-- Full character name ("First Last"), or nil when the unit doesn't exist or the name is unreadable.
-- No tooltip-scan fallback for secret names: the tooltip shows the same hidden name, and feeding a unit with a secret
-- GUID through a scan tooltip taints Blizzard's tooltip code in combat ([in-game] "Lua Taint: Bulwark" from
-- GameTooltip SetWatch, kb/gotchas.md#tooltip-scan-taint).
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
    return name
end

-- Names of the addon restrictions active right now ("Chat,Combat"), or "none". For diagnostics.
function Utils.ActiveRestrictions()
    local actions, types = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    local active = {}
    if actions and actions.IsAddOnRestrictionActive and type(types) == "table" then
        for name, value in pairs(types) do
            local ok, on = pcall(actions.IsAddOnRestrictionActive, value)
            if ok and on == true then table.insert(active, name) end
        end
        table.sort(active)
    end
    return #active > 0 and table.concat(active, ",") or "none"
end

-- True while the game restricts addon chat (Enum.AddOnRestrictionType.Chat: encounters, dungeon/raid maps...).
-- SendChatMessage is then blocked even from a click ([in-game] ADDON_ACTION_BLOCKED UNKNOWN(), kb/gotchas.md#chat-restricted).
function Utils.ChatRestricted()
    local actions = C_RestrictedActions
    local chat = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
    if not (actions and actions.IsAddOnRestrictionActive and chat) then return false end
    local ok, active = pcall(actions.IsAddOnRestrictionActive, chat)
    return ok and active == true
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
