local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Briefing build step 3 (kb/addons/Bulwark-Briefing.md): a tile that appears when the pack in view needs a briefing,
-- and a key ("Post briefing") that posts it. "No tile = nothing to brief."
-- Shown only out of combat, outside boss encounters and the Chat restriction, inside an instance, in a group, with the
-- option on, when a mob in view has a must cast or a boss in view has anything worth saying. After a post it stays
-- hidden until the briefing would read differently (another pack, new marks, other interrupters).
-- A plain button (nothing protected): hiding it in combat is allowed, and posting is plain party chat.
local Tile = MK:RegisterModule("BriefingTile")
local L, Briefing = MK.L, MK.Briefing

local SIZE = 36
local ICON = "Interface\\Icons\\Ability_Kick"
local BINDING = "CLICK BWK_BriefButton:LeftButton"

local tile
local inEncounter = false
local postedText          -- the briefing last posted: the tile stays hidden while it's still the same
local preview = false     -- Edit Mode: show a sample so the tile can be placed
local soloTest = false    -- /bwk mark brief test: also show the tile solo (this session only)
local refreshQueued = false
Tile.current = nil        -- { mobs, lines, text, label } of the briefing the tile offers

-- =========================================================================
-- Pure part
-- =========================================================================

-- Worth a tile: a mob with a must cast or a fear a shaman's Tremor Totem covers (item.totem, after Assign), or a boss
-- with anything listed (its should goes to the tank).
function Briefing.Worth(mobs)
    for _, mob in ipairs(mobs) do
        for _, item in ipairs(mob.spells) do
            if item.prio == "must" or item.totem or mob.boss then return true end
        end
    end
    return false
end

-- "Brief: {rt8} Ragefire Shaman, 2x Ragefire Shaman" (the mobs that made it worth a tile)
function Briefing.TileLabel(mobs)
    local names = {}
    for _, mob in ipairs(mobs) do
        local listed = false
        for _, item in ipairs(mob.spells) do
            if item.prio == "must" or item.totem or mob.boss then listed = true end
        end
        if listed then names[#names + 1] = Briefing.MobLabel(mob) end
    end
    return string.format(L["BRIEF_TILE_LABEL"], table.concat(names, ", "))
end

-- =========================================================================
-- Frame
-- =========================================================================

local Display = Briefing.Display

local function ReadPosition()
    local left, top = tile:GetLeft(), tile:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return { x = left, y = top }
end

local function RestorePosition()
    local p = MK.db and MK.db.briefTilePoint
    tile:ClearAllPoints()
    if p and tonumber(p.x) and tonumber(p.y) then
        tile:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        tile:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["BRIEF_TILE_TITLE"], 1, 1, 1)
    local cur = Tile.current
    if preview or not cur then
        GameTooltip:AddLine(L["BRIEF_TILE_PREVIEW"], 1, 0.82, 0, true)
    else
        for _, l in ipairs(cur.lines) do GameTooltip:AddLine(Display(l), 1, 1, 1, true) end
    end
    local key = GetBindingKey(BINDING)
    GameTooltip:AddLine(key and string.format(L["BRIEF_TILE_HINT_KEY"], key) or L["BRIEF_TILE_HINT"], 0.6, 0.8, 1, true)
    GameTooltip:Show()
end

local function Create()
    local b = CreateFrame("Button", "Bulwark_BriefTile", UIParent)
    b:SetSize(SIZE, SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    if b.SetDontSavePosition then b:SetDontSavePosition(true) end   -- our own saved position
    b:RegisterForClicks("LeftButtonUp")
    pcall(b.SetPassThroughButtons, b, "RightButton")             -- hold-right-click turning still works over it
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ICON)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -6, 6)
    b.border:SetPoint("BOTTOMRIGHT", 6, -6)
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetVertexColor(1, 0.8, 0.2)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.label:SetJustifyH("LEFT")
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() Tile.Post() end)
    b:Hide()
    tile = b
    RestorePosition()
end

-- =========================================================================
-- When to show it
-- =========================================================================

-- Why the tile is hidden right now (a key for /bwk mark brief status and tests), or nil when it may show.
function Tile.Blocker()
    if not MK.isEnabled then return "off" end
    if not MK:Get("briefTile") then return "option" end
    if InCombatLockdown() then return "combat" end
    if inEncounter then return "encounter" end
    if NS.Utils.ChatRestricted() then return "chat" end
    if not MK.Plates.inInstance then return "world" end
    if not IsInGroup() and not soloTest then return "solo" end
    return nil
end

function Tile:Refresh()
    if not tile then return end
    if preview then
        tile.label:SetText(string.format(L["BRIEF_TILE_LABEL"], "Ragefire Shaman"))
        tile:Show()
        return
    end
    Tile.current = nil
    if Tile.Blocker() then
        tile:Hide()
        return
    end
    local mobs = Briefing.Plan()
    if not Briefing.Worth(mobs) then
        tile:Hide()
        return
    end
    local lines = Briefing.BuildLines(mobs)
    local text = table.concat(lines, "\n")
    if #lines == 0 or text == postedText then
        tile:Hide()
        return
    end
    local label = Briefing.TileLabel(mobs)
    Tile.current = { mobs = mobs, lines = lines, text = text, label = label }
    tile.label:SetText(Display(label))
    tile:Show()
end

-- Many events come in bursts (plates, marks, targets): one refresh per frame burst.
local function Queue()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        Tile:Refresh()
    end)
end
Tile.Queue = Queue

-- Click, key or /bwk mark brief: post, then stay hidden until the briefing changes.
function Tile.Post()
    if preview then return end
    local lines = Briefing.Post()
    if lines then
        postedText = table.concat(lines, "\n")
        Tile:Refresh()
    end
end

-- Key binding target: an invisible button, so the key works whether or not the tile is shown.
local keyButton = CreateFrame("Button", "BWK_BriefButton", UIParent)
keyButton:RegisterForClicks("AnyDown", "AnyUp")
local lastKey = -math.huge
keyButton:SetScript("OnClick", function()
    local now = GetTime()
    if now - lastKey < 0.5 then return end   -- a key press can deliver both halves of the click: act once
    lastKey = now
    if MK.isEnabled then Tile.Post() end
end)

local frame = CreateFrame("Frame", "Bulwark_BriefTileFrame")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if tile and not preview then tile:Hide() end   -- at once, not after the queue delay
        return
    elseif event == "ENCOUNTER_START" then
        inEncounter = true
        if tile and not preview then tile:Hide() end
        return
    elseif event == "ENCOUNTER_END" then
        inEncounter = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        inEncounter, postedText = false, nil
    end
    Queue()
end)

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END",
                 "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PLAYER_ENTERING_WORLD",
                 "ZONE_CHANGED_NEW_AREA" }

-- /bwk mark brief test: show the tile solo too (until /reload), for trying it out without a group.
function Tile.ToggleSoloTest()
    soloTest = not soloTest
    MK:Print(soloTest and L["BRIEF_TEST_ON"] or L["BRIEF_TEST_OFF"])
    Tile:Refresh()
end

-- /bwk mark brief status
function Tile.Status()
    local why = Tile.Blocker()
    if why then
        MK:Print(L["BRIEF_STATUS_HIDDEN"], L["BRIEF_BLOCK_" .. why])
    elseif Tile.current then
        MK:Print(L["BRIEF_STATUS_SHOWN"], Display(Tile.current.label))
    else
        MK:Print(L["BRIEF_STATUS_NOTHING"])
    end
end

function Tile:OnInitialize()
    MK:On("PLAN_CHANGED", Queue)
    MK:On("MOB_LEARNED", Queue)
    MK:On("SETUP_CHANGED", Queue)
    MK:On("BRIEFING_CHANGED", Queue)
end

function Tile:OnEnable()
    if not tile then Create() end
    for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    Queue()
end

function Tile:OnDisable()
    frame:UnregisterAllEvents()
    Tile.current = nil
    if tile then tile:Hide() end
end

function Tile:GetFrame() return tile end   -- tests

-- Blizzard's HUD Edit Mode: the tile shows a sample so it can be placed; moves wait for Blizzard's Save.
NS.EditMode:Register({
    label = L["BRIEF_TILE_TITLE"],
    GetFrame = function() return tile end,
    IsAvailable = function() return tile ~= nil and MK.isEnabled and tile:IsShown() end,
    Read = function() return ReadPosition() end,
    Save = function(pos) if pos then MK.db.briefTilePoint = pos end end,
    Restore = function() if tile then RestorePosition() end end,
    OnEnter = function()
        if not tile or not MK.isEnabled or not MK:Get("briefTile") then return end
        preview = true
        Tile:Refresh()
    end,
    OnExit = function()
        if not preview then return end
        preview = false
        Tile:Refresh()
    end,
})
