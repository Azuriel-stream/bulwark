local ADDON_NAME, NS = ...
local MK = NS.Marking

-- The team setup: kill order and CC assignments for the run (one active setup), the group roster, and the
-- announcement that tells the group the order. Group members' names/classes are never secret (kb/restrictions.md §2b).
local Team = MK:RegisterModule("Team")
local L, Utils = MK.L, MK.Utils

-- Class -> the CC it brings (announcement text)
Team.CC_SPELL = {
    MAGE = "CC_MAGE", ROGUE = "CC_ROGUE", WARLOCK = "CC_WARLOCK", HUNTER = "CC_HUNTER",
    PRIEST = "CC_PRIEST", DRUID = "CC_DRUID",
}

local function Separator()
    local c = Constants and Constants.CharacterNameSeparatorConsts
    local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
    return type(sep) == "string" and sep or " "
end

-- Forever: UnitName's second return is the surname; a full name is "First Last" (kb/api-migration.md).
function Team.FullName(unit)
    local first, surname = UnitName(unit)
    first = Utils.Safe(first, "string", nil)
    if not first then return nil end
    surname = Utils.Safe(surname, "string", nil)
    if surname and surname ~= "" then return first .. Separator() .. surname end
    return first
end

-- Group members including the player: { unit, name, short, class, race, alive }
function Team:Members()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do table.insert(units, "raid" .. i) end
    else
        table.insert(units, "player")
        for i = 1, GetNumSubgroupMembers() do table.insert(units, "party" .. i) end
    end
    local list = {}
    for _, unit in ipairs(units) do
        local name = Team.FullName(unit)
        if name then
            local _, class = UnitClass(unit)
            local _, race = UnitRace(unit)
            table.insert(list, {
                unit = unit, name = name, short = (UnitName(unit)), class = class, race = race,
                alive = not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) ~= false,
            })
        end
    end
    return list
end

function Team:FindMember(name)
    if not name then return nil end
    for _, m in ipairs(Team:Members()) do
        if m.name == name then return m end
    end
    return nil
end

function Team:Rows()
    return MK.char.setup.rows
end

-- Saved setups from before the Tank/CC split: "KILL" is now "TANK", "OFF" is a tank row switched off.
function Team.Migrate(rows)
    for _, row in ipairs(rows) do
        if row.role == "OFF" then
            row.role, row.off = "TANK", true
        elseif row.role ~= "CC" and row.role ~= "FOLLOW" then
            row.role = "TANK"
        end
    end
end

-- Tank icons in kill order. Every mob dies; the role says whether a mark is tanked or crowd-controlled first.
-- Rows switched off (HUD) are left out, and a row owned by a tank is skipped while that tank is dead, offline or gone.
function Team:GetLadder()
    local ladder = {}
    for _, row in ipairs(Team:Rows()) do
        if row.role == "TANK" and not row.off then
            local owner = row.player and Team:FindMember(row.player)
            if not row.player or (owner and owner.alive) then table.insert(ladder, row.icon) end
        end
    end
    return ladder
end

-- Tank icons that are on (for the next-free-icon key), regardless of owners.
function Team:KillIcons()
    local icons = {}
    for _, row in ipairs(Team:Rows()) do
        if row.role == "TANK" and not row.off then table.insert(icons, row.icon) end
    end
    return icons
end

-- CC rows whose player is in the group: { mark, class, race, alive } (Rules.SelectCCSlot input)
function Team:GetCCSlots()
    local slots = {}
    for _, row in ipairs(Team:Rows()) do
        if row.role == "CC" and row.player and not row.off then
            local m = Team:FindMember(row.player)
            if m and MK.Rules.HasCC(m.class) then   -- a Shaman's row stays empty (no CC on Forever)
                table.insert(slots, { mark = row.icon, class = m.class, race = m.race, alive = m.alive })
            end
        end
    end
    return slots
end

-- Follow rows put their mark on a group member (the tank) so the group can follow them.
-- Icons of every Follow row: never planned on a mob, even while the row is off.
function Team:FollowIcons()
    local icons = {}
    for _, row in ipairs(Team:Rows()) do
        if row.role == "FOLLOW" then icons[row.icon] = true end
    end
    return icons
end

-- Follow rows that are on and whose player is in the group: { icon, unit }. The unit token is read out of combat
-- (secure attributes); "player" for yourself, since it never changes when the roster does.
function Team:GetFollows()
    local follows = {}
    local me = Team.FullName("player")
    for _, row in ipairs(Team:Rows()) do
        if row.role == "FOLLOW" and row.player and not row.off then
            local m = Team:FindMember(row.player)
            if m then
                table.insert(follows, { icon = row.icon, unit = (m.name == me) and "player" or m.unit })
            end
        end
    end
    return follows
end

-- =========================================================================
-- Editing (setup window)
-- =========================================================================
-- Skull can't be a Follow mark: the next-skull key moves skull, which would take it off the tank.
local ROLE_CYCLE = { TANK = "CC", CC = "FOLLOW", FOLLOW = "TANK" }

local function Changed()
    MK:Fire("SETUP_CHANGED")
    if MK.Plates then MK.Plates.Changed() end
end

function Team:CycleRole(i)
    local row = Team:Rows()[i]
    row.role = ROLE_CYCLE[row.role] or "TANK"
    if row.role == "FOLLOW" and row.icon == 8 then row.role = "TANK" end
    Changed()
end

-- On/off is separate from the role: the leader switches marks off for the pack in front of them (HUD).
-- Out of combat the plan and keys follow at once; a change made in combat applies when combat ends.
function Team:ToggleOff(i)
    local row = Team:Rows()[i]
    row.off = not row.off or nil
    Changed()
end

function Team:AllOn()
    for _, row in ipairs(Team:Rows()) do row.off = nil end
    Changed()
end

function Team:AnyOff()
    for _, row in ipairs(Team:Rows()) do
        if row.off then return true end
    end
    return false
end

-- From the player dropdown: a member's full name, or nil for none.
function Team:SetPlayer(i, name)
    Team:Rows()[i].player = name
    Changed()
end

function Team:ClearPlayer(i)
    Team:Rows()[i].player = nil
    Changed()
end

function Team:MoveRow(i, delta)
    local rows = Team:Rows()
    local j = i + delta
    if j < 1 or j > #rows then return end
    rows[i], rows[j] = rows[j], rows[i]
    Changed()
end

function Team:Reset()
    MK.char.setup = MK.CopyTable(MK.DefaultCharConfig.setup)
    Changed()
end

-- =========================================================================
-- Announcement, up to three lists:
--   "[Bulwark] Kill order: {rt8} Twilight Grunt (Tankard) > {rt7} Krol'dok Brute"
--   "[Bulwark] CC: {rt5} Ragefire Shaman: Lumen (Polymorph)"
--   "[Bulwark] Follow: {rt1} Tankard"
-- Mob names come from the mobs wearing the icons (Learn.MobsByIcon: our own marks, then marks learned from the %t
-- echo). Once any kill icon sits on a known mob, the kill list names the pack only; with none (before marking, or
-- learning off) it lists every kill icon as before.
-- =========================================================================
local MAX_LINE = 250   -- chat messages are cut at 255 characters

local function ShortName(full)
    local m = Team:FindMember(full)
    return (m and m.short) or (full and full:match("^(%S+)")) or full
end

-- "label a > b > c", split over several lines (each with the label) when it gets too long for one message.
local function Wrap(label, items, sep)
    local lines, current = {}, nil
    local head = L["ANNOUNCE_PREFIX"] .. " " .. label .. " "
    for _, item in ipairs(items) do
        if current and #current + #sep + #item > MAX_LINE then
            table.insert(lines, current)
            current = nil
        end
        current = current and (current .. sep .. item) or (head .. item)
    end
    if current then table.insert(lines, current) end
    return lines
end

function Team:BuildAnnouncement()
    local mobs = MK.Learn and MK.Learn.MobsByIcon() or {}
    local function MobName(icon)
        local rec = mobs[icon]
        return rec and MK.Learn.NameOf(rec)
    end
    local kill, killNamed, cc, follow = {}, {}, {}, {}
    for _, row in ipairs(Team:Rows()) do
        local icon = "{rt" .. row.icon .. "}"
        local mob = MobName(row.icon)
        if row.role == "TANK" and not row.off then
            local owner = row.player and ShortName(row.player)
            table.insert(kill, owner and (icon .. " " .. owner) or icon)
            if mob then table.insert(killNamed, icon .. " " .. mob .. (owner and (" (" .. owner .. ")") or "")) end
        elseif row.role == "CC" and row.player and not row.off then
            local m = Team:FindMember(row.player)
            local spell = m and Team.CC_SPELL[m.class]
            table.insert(cc, icon .. " " .. (mob and (mob .. ": ") or "") .. ShortName(row.player)
                .. (spell and (" (" .. L[spell] .. ")") or ""))
        elseif row.role == "FOLLOW" and row.player and not row.off then
            table.insert(follow, icon .. " " .. ShortName(row.player))
        end
    end
    -- One list per line, each with its own label (player chat can't carry custom colours).
    -- Never a bare "|" in chat: it starts an escape sequence and the client rejects the message.
    local lines = Wrap(L["ANNOUNCE_KILL"], #killNamed > 0 and killNamed or kill, " > ")
    if #lines == 0 then lines = { L["ANNOUNCE_PREFIX"] .. " " .. L["ANNOUNCE_KILL"] } end
    for _, l in ipairs(Wrap(L["ANNOUNCE_CC"], cc, ", ")) do table.insert(lines, l) end
    for _, l in ipairs(Wrap(L["ANNOUNCE_FOLLOW"], follow, ", ")) do table.insert(lines, l) end
    return lines
end

function Team:Announce()
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
    if channel and NS.Utils.ChatRestricted() then   -- Bulwark: blocked while addon chat is restricted
        MK:Print(NS.L["MSG_CHAT_RESTRICTED"])
        channel = nil
    end
    for _, msg in ipairs(Team:BuildAnnouncement()) do
        if not channel then
            MK:Print(L["ANNOUNCE_SOLO"], msg)
        else
            local ok, err = pcall(C_ChatInfo.SendChatMessage, msg, channel)
            if not ok then MK:Print(L["ANNOUNCE_FAILED"], tostring(err), msg) end
        end
    end
end

-- The roster changes who owns which icon: re-plan.
local frame = CreateFrame("Frame", "BWK_TeamFrame")
frame:SetScript("OnEvent", function()
    Changed()
end)

function Team:OnInitialize()
    Team.Migrate(Team:Rows())
end

function Team:OnEnable()
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
end

function Team:OnDisable()
    frame:UnregisterAllEvents()
end
