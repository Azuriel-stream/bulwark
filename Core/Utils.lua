local ADDON_NAME, NS = ...

-- Shared secret-safe helpers. One copy for every area; the areas' own helpers join here when they're ported
-- (merged from TankAlertForever/TankAuditForever/TankMarkForever Core/Utils.lua).
local Utils = {}
NS.Utils = Utils

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

-- "RAID", "PARTY" or "SOLO".
function Utils.GetGroupType()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return "SOLO"
end
