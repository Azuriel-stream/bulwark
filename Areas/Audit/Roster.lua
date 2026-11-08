local ADDON_NAME, NS = ...

-- Group composition: which classes are present (and in the player's raid subgroup), with levels.
-- Group members' identities and levels are never secret on Forever (kb/restrictions.md §2b).
-- (from TankAuditForever Modules/Roster.lua)
local Roster = NS:RegisterModule("AuditRoster", "audit")

Roster.classes = {}          -- [classFile] = online count, including the player
Roster.subgroupClasses = {}  -- [classFile] = count in the player's subgroup (party = whole group)
Roster.members = {}          -- { class, level, isPlayer } for online members, including the player
Roster.isSolo = true

local function Add(class, level, inSubgroup, isPlayer)
    Roster.classes[class] = (Roster.classes[class] or 0) + 1
    if inSubgroup then
        Roster.subgroupClasses[class] = (Roster.subgroupClasses[class] or 0) + 1
    end
    table.insert(Roster.members, { class = class, level = level or 0, isPlayer = isPlayer })
end

function Roster:Update()
    wipe(self.classes)
    wipe(self.subgroupClasses)
    wipe(self.members)
    self.isSolo = not IsInGroup()

    if IsInRaid() then
        local count = GetNumGroupMembers()
        local mySubgroup, myIndex = 1, nil
        for i = 1, count do
            if UnitIsUnit("raid" .. i, "player") then
                local _, _, subgroup = GetRaidRosterInfo(i)
                mySubgroup, myIndex = subgroup or 1, i
                break
            end
        end
        for i = 1, count do
            local _, _, subgroup, level, _, class, _, online = GetRaidRosterInfo(i)
            if online and class then
                Add(class, level, subgroup == mySubgroup, i == myIndex)
            end
        end
        return
    end

    Add(NS.playerClass, UnitLevel("player"), true, true)
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party" .. i
        local _, class = UnitClass(unit)
        if class and UnitIsConnected(unit) then
            Add(class, UnitLevel(unit), true, false)
        end
    end
end

-- Count of a class in the group, not counting the player.
function Roster:CountOthers(class, subgroupOnly)
    local count = (subgroupOnly and self.subgroupClasses or self.classes)[class] or 0
    if class == NS.playerClass then count = count - 1 end
    return count
end

-- Count including the player.
function Roster:Count(class, subgroupOnly)
    return (subgroupOnly and self.subgroupClasses or self.classes)[class] or 0
end

-- True if someone other than the player has the class and level to remove this debuff type.
-- requirements = { [classFile] = minimum level } (Data.lua DISPEL_LEVELS)
function Roster:OthersCanDispel(requirements)
    for _, m in ipairs(self.members) do
        local minLevel = requirements[m.class]
        if not m.isPlayer and minLevel and m.level >= minLevel then return true end
    end
    return false
end
