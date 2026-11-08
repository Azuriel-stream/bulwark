local ADDON_NAME, NS = ...
local Utils, D = NS.Utils, NS.AuditData

-- When a requested buff arrives, whisper its caster a thank-you. AuraData.sourceUnit names the actual caster, and
-- group members' names aren't secret on Forever. (from TankAuditForever Modules/Gratitude.lua)
local Gratitude = NS:RegisterModule("AuditGratitude", "audit")

local REQUEST_WINDOW = 60  -- seconds after a request during which a new buff counts as the answer

function Gratitude:Check(helpfulAuras)
    local Requests = NS.AuditRequests
    local pending = Requests.pending
    if not pending then return end
    if (GetTime() - pending.time) > REQUEST_WINDOW then
        Requests.pending = nil
        return
    end
    for _, aura in ipairs(helpfulAuras) do
        if pending.ids[aura.spellId] then
            Requests.pending = nil
            if not NS.db.audit.gratitude then return end
            local source = aura.sourceUnit
            if not source or Utils.IsSecret(source) or not UnitExists(source) or UnitIsUnit(source, "player") then
                return
            end
            local target = Utils.GetUnitFullName(source)
            local firstName = Utils.SafeString((UnitName(source)), nil)
            if target and firstName then
                local text = D.THANKS[math.random(1, #D.THANKS)]
                C_ChatInfo.SendChatMessage(string.format(text, pending.spellText, firstName), "WHISPER", nil, target)
            end
            return
        end
    end
end
