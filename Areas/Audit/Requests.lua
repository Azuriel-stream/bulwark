local ADDON_NAME, NS = ...
local Utils, D, L = NS.Utils, NS.AuditData, NS.L

-- Lua side of tile clicks: chat requests and opening bags. Casting and cancelling are done by the secure buttons
-- themselves (Bar.lua). (from TankAuditForever Modules/Requests.lua)
local Requests = NS:RegisterModule("AuditRequests", "audit")

local REQUEST_THROTTLE = 5   -- seconds per buff
local lastSent = {}

-- The latest request, for Gratitude.lua: { ids = set, time, spellText }
Requests.pending = nil

local function Pick(list)
    return list[math.random(1, #list)]
end

local LOCAL_HINTS = {
    WELL_FED = "MSG_LOCAL_FOOD",
    WEAPON_BUFF = "MSG_LOCAL_WEAPON",
    ELIXIR = "MSG_LOCAL_ELIXIR",
    FLASK = "MSG_LOCAL_FLASK",
}

function Requests:BuildMessage(entry)
    if entry.kind == "debuff" then
        -- The debuff itself is secret in combat; the tile knows its dispel type
        return string.format(L["MSG_NEED_DISPEL_TYPE"], L[entry.dispelType] or entry.dispelType or "?")
    end
    if entry.key == "HEALTHSTONE" then
        return L["MSG_NEED_HS"]
    end
    local spellText = Utils.SpellChatName(entry.spellId, entry.label)
    local msg = string.format(Pick(D.REQUESTS[entry.messageKey] or D.REQUESTS.DEFAULT), spellText)
    if entry.expiresAt and entry.expiresAt > 0 then -- clicked while expiring: say when it fades
        local left = entry.expiresAt - GetTime()
        if left > 0 then
            msg = msg .. string.format(L["MSG_EXPIRING_SUFFIX"], Utils.FormatTime(left))
        end
    end
    return msg
end

function Requests:Request(entry)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
    if not channel then
        NS:Print(L["MSG_SOLO"])
        return
    end
    local now = GetTime()
    local throttleKey = entry.key .. (entry.dispelType or entry.label or "")
    if lastSent[throttleKey] and (now - lastSent[throttleKey]) < REQUEST_THROTTLE then
        NS:Print(L["MSG_WAIT_THROTTLE"])
        return
    end
    lastSent[throttleKey] = now

    C_ChatInfo.SendChatMessage(self:BuildMessage(entry), channel)
    if entry.watchIds then
        Requests.pending = { ids = entry.watchIds, time = now, spellText = Utils.SpellChatName(entry.spellId, entry.label) }
    end
end

-- From the tiles' OnClick hook (a hardware event, so chat is allowed in combat too).
function Requests:OnClick(entry)
    local action = entry and entry.action
    if not action then return end
    if action.type == "request" then
        self:Request(entry)
    elseif action.type == "bags" then
        OpenAllBags()
        local hint = LOCAL_HINTS[entry.key]
        if hint then NS:Print(L[hint]) end
    end
end

function Requests:OnDisable()
    wipe(lastSent)
    Requests.pending = nil
end
