local ADDON_NAME, NS = ...
local Utils, D = NS.Utils, NS.AuditData

-- When a requested buff arrives, whisper its caster a thank-you. AuraData.sourceUnit names the actual caster, and
-- group members' names aren't secret on Forever. (from TankAuditForever Modules/Gratitude.lua)
local Gratitude = NS:RegisterModule("AuditGratitude", "audit")

local REQUEST_WINDOW = 60  -- seconds after a request during which a new buff counts as the answer

-- Only a fresh application answers the request. When the tile was clicked while the buff was still up (expiring),
-- that old copy is on the player at every scan; it only counts once a recast pushes its expiry past the old one.
local function IsNewer(aura, oldExpiry)
    if oldExpiry == nil then return true end           -- it was missing when we asked
    local expires = aura.expirationTime
    if not expires or Utils.IsSecret(expires) then return false end
    return expires > oldExpiry + 1
end

function Gratitude:Check(helpfulAuras)
    local Requests = NS.AuditRequests
    local pending = Requests.pending
    if not pending then return end
    if (GetTime() - pending.time) > REQUEST_WINDOW then
        Requests.pending = nil
        return
    end
    for _, aura in ipairs(helpfulAuras) do
        if pending.ids[aura.spellId] and IsNewer(aura, pending.oldExpiry) then
            Requests.pending = nil
            if not NS.db.audit.gratitude then return end
            local source = aura.sourceUnit
            if not source or Utils.IsSecret(source) or not UnitExists(source) or UnitIsUnit(source, "player") then
                return
            end
            local target = Utils.GetUnitFullName(source)
            local firstName = Utils.SafeString((UnitName(source)), nil)
            if target and firstName and not Utils.ChatRestricted() then
                local text = D.THANKS[math.random(1, #D.THANKS)]
                C_ChatInfo.SendChatMessage(string.format(text, pending.spellText, firstName), "WHISPER", nil, target)
            end
            return
        end
    end
end
