local ADDON_NAME, NS = ...
local L, Kit, Gear = NS.L, NS.Kit, NS.GearAudit
local C = Kit.C

-- Mats tracker: the Enchant list's mats on screen, in the style of the quest tracker (kb/addons/Bulwark-Utilities.md
-- "Step 4"). One line per mat, "have/need Name"; a line greys out with a tick once there are enough (bags + bank).
-- Blizzard's own recipe tracker can't hold a summed list or recipes the character doesn't know, so this is our frame.
-- Drag the header to move it; shift-click a line to link the item (chat, auction house search).
local Tracker = NS:RegisterModule("MatsTracker", "utilities")

NS.DefaultCharConfig.gear.tracker = {
    shown = false,      -- turned on from the Enchant list page
    -- x, y: top-left in UIParent coordinates (nil = default spot under the minimap)
}

local WIDTH, LINE_H, MAX_LINES = 230, 15, 20
local DONE = { 0.55, 0.55, 0.55, 1 }
local frame, lines = nil, {}
Tracker.lines = lines        -- for tests
local events = CreateFrame("Frame")

local function cfg() return NS.char.gear.tracker end

local function SavePosition()
    local x, y = frame:GetLeft(), frame:GetTop()
    if type(x) == "number" and type(y) == "number" then
        cfg().x, cfg().y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
end

local function ApplyPosition()
    frame:ClearAllPoints()
    if cfg().x and cfg().y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg().x, cfg().y)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -260)
    end
end

local function ItemLink(id)
    local ok, _, link = pcall(C_Item.GetItemInfo, id)
    return ok and link or nil
end

local function Line(i)
    local line = CreateFrame("Button", nil, frame)
    line:SetHeight(LINE_H)
    line:SetPoint("TOPLEFT", 4, -24 - (i - 1) * LINE_H)
    line:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    line.tick = line:CreateTexture(nil, "ARTWORK")
    line.tick:SetSize(12, 12)
    line.tick:SetPoint("LEFT", 0, 0)
    line.tick:SetAtlas("ui-questtracker-tracker-check")   -- the quest tracker's own tick
    line.text = Kit.Text(line, 12)
    line.text:SetPoint("LEFT", 16, 0)
    line.text:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.text:SetWordWrap(false)
    line:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not (GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, self.item)) then
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
        end
        GameTooltip:AddLine(L["TRACKER_TIP_LINK"], C.muted[1], C.muted[2], C.muted[3], true)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    line:SetScript("OnClick", function(self)
        local link = self.item and ItemLink(self.item)
        if link and IsModifiedClick and IsModifiedClick("CHATLINK") and HandleModifiedItemClick then
            HandleModifiedItemClick(link)
        end
    end)
    return line
end

local function Create()
    frame = CreateFrame("Frame", "BulwarkMatsTracker", UIParent)
    frame:SetSize(WIDTH, 40)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()

    local header = CreateFrame("Button", nil, frame)
    header:SetHeight(20)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["TRACKER_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["TRACKER_TIP_HEADER"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header:SetScript("OnClick", function()
        if NS.Window and NS.Window.Open then NS.Window:Open("utilities", "enchantlist") end
    end)
    frame.title = Kit.Text(header, 14, C.goldText)
    frame.title:SetPoint("LEFT", 4, 0)
    frame.count = Kit.Text(header, 11, C.muted)
    frame.count:SetPoint("RIGHT", -4, 0)
    Kit.FadeLine(frame, -20, C.goldDim)
    frame.note = Kit.Text(frame, 12, C.muted)
    frame.note:SetPoint("TOPLEFT", 8, -26)
    ApplyPosition()
end

-- Lines for the tracker: { item, need, have, name, done }, in the Enchant list order (Gear.SortMats); done lines
-- stay in place, greyed out with a tick.
function Tracker.Lines()
    local _, mats = Gear.ShoppingList()
    local out = {}
    for _, m in ipairs(mats) do
        local have = Gear.Have(m.item)
        out[#out + 1] = { item = m.item, need = m.need, have = have, name = m.name, done = have >= m.need }
    end
    return out
end

function Tracker:Refresh()
    if not frame then return end
    local open = Gear.OpenPicks()
    if not cfg().shown or open == 0 then
        frame:Hide()
        return
    end
    local data = Tracker.Lines()
    frame.title:SetText(L["TRACKER_TITLE"])
    frame.count:SetText(string.format(L["TRACKER_COUNT"], open))
    local ready = 0
    for _, d in ipairs(data) do if d.done then ready = ready + 1 end end
    frame.note:SetText(#data > 0 and ready == #data and L["TRACKER_ALL_READY"] or "")
    local shown = math.min(#data, MAX_LINES)
    for i = 1, math.max(shown, #lines) do
        local d = data[i]
        if d and not lines[i] then lines[i] = Line(i) end
        local line = lines[i]
        if line then
            line.item = d and d.item
            line:SetShown(d ~= nil and i <= shown)
            if d then
                line.text:SetText(string.format(L["TRACKER_LINE"], math.min(d.have, d.need), d.need, d.name))
                Kit.SetTextColor(line.text, d.done and DONE or C.text)
                line.tick:SetShown(d.done)
            end
        end
    end
    local noteH = frame.note:GetText() ~= "" and LINE_H + 4 or 0
    frame.note:ClearAllPoints()
    frame.note:SetPoint("TOPLEFT", 8, -26 - shown * LINE_H)
    frame:SetHeight(28 + shown * LINE_H + noteH)
    frame:Show()
end

function Tracker:SetShown(on)
    cfg().shown = on and true or false
    Tracker:Refresh()
end

function Tracker:ResetPosition()
    cfg().x, cfg().y = nil, nil
    if frame then ApplyPosition() end
end

local pending = false
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        Tracker:Refresh()
    end)
end

function Tracker:OnEnable()
    if not frame then Create() end
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "GET_ITEM_INFO_RECEIVED",
                         "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", Later)
    Tracker.enabled = true
    Later()
end

function Tracker:OnDisable()
    Tracker.enabled = false
    events:UnregisterAllEvents()
    events:SetScript("OnEvent", nil)
    if frame then frame:Hide() end
end

NS:On("GEAR_PICKS_CHANGED", function()
    if Tracker.enabled then Later() end
end)
