local ADDON_NAME, NS = ...
local MK = NS.Marking

local Utils = {}
MK.Utils = Utils

-- =========================================================================
-- Secret values (kb/restrictions.md). Mob identity is secret in combat everywhere and on restricted maps
-- (dungeons, raids) even out of combat.
-- =========================================================================
function Utils.IsSecret(val)
    if val == nil then return false end
    if issecretvalue then
        return issecretvalue(val) == true
    end
    -- Fallback for clients without the primitive: secrets error on concatenation
    return not pcall(function() return val .. "" end)
end

-- Returns val if it's a readable value of the expected type, otherwise fallback.
function Utils.Safe(val, kind, fallback)
    if val == nil or Utils.IsSecret(val) or type(val) ~= kind then
        return fallback
    end
    return val
end

-- Readable boolean result of a unit API (false when secret or erroring).
function Utils.Flag(fn, unit)
    local ok, v = pcall(fn, unit)
    return ok and v == true and not Utils.IsSecret(v)
end

-- Raid icon texture + texcoords (UI-RaidTargetingIcons is a 4x4 sheet, icon 1 top left).
Utils.ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
function Utils.IconTexCoord(icon)
    local i = icon - 1
    local col, row = i % 4, math.floor(i / 4)
    return col / 4, (col + 1) / 4, row / 4, (row + 1) / 4
end

-- Inline chat icon: {rt8} style text for print()
function Utils.IconText(icon)
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon .. ":0|t"
end

-- Group members' names and classes are never secret (kb/restrictions.md §2b).
function Utils.ClassColored(name, class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
    return name
end

function Utils.IconName(icon)
    return MK.L["ICON_" .. tostring(icon)]
end
