local ADDON_NAME, NS = ...
local Utils, L = NS.Utils, NS.L

-- Carrot on a Stick (user 2026-11-28; kb/addons/Bulwark.md "Audit: Carrot on a Stick"). Item 11122, trinket, +3 %
-- mount speed (spell 13587) [data: Forever Item + ItemXItemEffect]. Your own gear and bags are plain to addons, and
-- C_Item.EquipItemByName has no restriction annotation [docs]; the game refuses trinket swaps in combat, so the tile
-- only shows out of combat (and not dead, not on a flight path):
--  * mounted, the Carrot in your bags: a green tile; click = put it into the chosen trinket slot (audit.carrotSlot).
--    The trinket it replaces is remembered per character (BulwarkCharDB.carrotPrev).
--  * on foot for DELAY s with the Carrot on: an orange tile; click = a list of the trinkets in your bags (the
--    remembered one first); a pick goes into the Carrot's slot.
-- Every equip is checked CHECK_AFTER s later; a miss prints a line.
local CR = NS:RegisterModule("AuditCarrot", "audit")
NS.AuditCarrot = CR

local CARROT = 11122
CR.ITEM = CARROT
local SIZE = 32
local DELAY = 4                 -- seconds on foot before the swap tile shows (dismounting to loot or talk)
local CHECK_AFTER = 1.5
local SLOTS = { 13, 14 }
local FALLBACK_ICON = 134010    -- the Carrot's icon [data: Item.csv]
local COLOR_ON = { 0.25, 1, 0.35 }
local COLOR_SWAP = { 1, 0.6, 0.15 }

local frame, tile
local preview = false           -- Edit Mode
local windowPreview = false     -- the Bulwark window shows the Audit tab
local onFootSince = nil         -- GetTime() of the last dismount (nil while mounted or on a flight path)
local queued = false
local pending = nil             -- the last equip, checked CHECK_AFTER s later

local function cfg() return NS.db.audit end

-- =========================================================================
-- Pure part
-- =========================================================================

local function Equipped(slot)
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    if not ok or Utils.IsSecret(id) then return nil end
    return id
end

function CR.CarrotSlot()
    for _, s in ipairs(SLOTS) do
        if Equipped(s) == CARROT then return s end
    end
    return nil
end

function CR.ChosenSlot() return cfg().carrotSlot == 13 and 13 or 14 end

-- Trinkets in your bags: { itemID, link, name, icon, quality }.
function CR.BagTrinkets()
    local list = {}
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do   -- backpack + 4 bags (Blizzard_FrameXMLBase/Constants.lua)
        local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
        if okN and type(n) == "number" then
            for slot = 1, n do
                local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                local id = okI and type(info) == "table" and info.itemID
                if type(id) == "number" then
                    local okE, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, id)
                    if okE and equipLoc == "INVTYPE_TRINKET" then
                        list[#list + 1] = { itemID = id, link = info.hyperlink, name = info.itemName,
                                            icon = info.iconFileID, quality = info.quality }
                    end
                end
            end
        end
    end
    return list
end

function CR.CarrotInBags()
    for _, t in ipairs(CR.BagTrinkets()) do
        if t.itemID == CARROT then return true end
    end
    return false
end

local function Mounted()
    local ok, m = pcall(IsMounted)
    return ok and m == true
end

local function OnTaxi()
    local ok, t = pcall(UnitOnTaxi, "player")
    return ok and t == true
end

local function Dead()
    local ok, d = pcall(UnitIsDeadOrGhost, "player")
    return ok and d == true
end

-- What the tile should do now: "puton", "swap", or nil plus why not (status, tests).
function CR.State()
    if not NS:IsAreaRunning("audit") then return nil, "off" end
    if not cfg().carrot then return nil, "option" end
    if InCombatLockdown() then return nil, "combat" end
    if Dead() then return nil, "dead" end
    if OnTaxi() then return nil, "taxi" end
    local slot = CR.CarrotSlot()
    if Mounted() then
        if slot then return nil, "wearing" end
        return CR.CarrotInBags() and "puton" or nil, "none"
    end
    if not slot then return nil, "none" end
    if not onFootSince or GetTime() - onFootSince < DELAY then return nil, "waiting" end
    return "swap"
end

-- =========================================================================
-- Equipping
-- =========================================================================

local function Name(itemID, fallback)
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    return (ok and type(name) == "string" and name) or fallback or ("item " .. tostring(itemID))
end

local function Verify()
    local p = pending
    if not p then return end
    pending = nil
    local now = Equipped(p.slot)
    local good = now == p.itemID
    if not good then NS:Print(L["CARROT_FAILED"], Name(p.itemID, p.name), p.slot) end
    CR.Queue()
end

-- item = item ID or link; itemID = what the slot should hold afterwards.
local function Equip(item, itemID, slot, name)
    if InCombatLockdown() then
        NS:Print(L["CARROT_COMBAT"])
        return
    end
    pcall(C_Item.EquipItemByName, item, slot)
    pending = { slot = slot, itemID = itemID, name = name }
    C_Timer.After(CHECK_AFTER, Verify)
end

function CR.PutOn()
    local slot = CR.ChosenSlot()
    local prev = Equipped(slot)
    if prev and prev ~= CARROT then NS.char.carrotPrev = { itemID = prev, slot = slot } end
    Equip(CARROT, CARROT, slot)
end

-- The swap list: the remembered trinket first, then the rest by name; one row per item.
function CR.SwapOptions()
    local prev = NS.char.carrotPrev and NS.char.carrotPrev.itemID
    local items, seen = {}, {}
    for _, t in ipairs(CR.BagTrinkets()) do
        if t.itemID ~= CARROT and not seen[t.itemID] then
            seen[t.itemID] = true
            items[#items + 1] = t
        end
    end
    table.sort(items, function(a, b)
        if (a.itemID == prev) ~= (b.itemID == prev) then return a.itemID == prev end
        return (a.name or "") < (b.name or "")
    end)
    local options = { { header = true, label = L["CARROT_LIST_HEADER"] } }
    for _, t in ipairs(items) do
        local name = t.name or Name(t.itemID)
        local color
        if t.quality then
            local ok, r, g, b = pcall(C_Item.GetItemQualityColor, t.quality)
            if ok and type(r) == "number" then color = { r, g, b, 1 } end
        end
        options[#options + 1] = {
            key = t.itemID, link = t.link, name = name, icon = t.icon, color = color,
            label = t.itemID == prev and string.format(L["CARROT_WAS_HERE"], name) or name,
        }
    end
    if #items == 0 then options[#options + 1] = { header = true, label = L["CARROT_NO_TRINKETS"] } end
    return options
end

function CR.OpenSwap(owner)
    local slot = CR.CarrotSlot()
    if not slot then return end
    NS.Kit.OpenList(owner, CR.SwapOptions(), nil, function(itemID, o)
        Equip(o.link or itemID, itemID, slot, o.name)
    end, 240)
end

-- =========================================================================
-- Frame
-- =========================================================================

local function RestorePosition()
    local p = cfg().carrotPoint
    frame:ClearAllPoints()
    if p and tonumber(p.x) and tonumber(p.y) then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -SIZE / 2, -195)
    end
end

local function ReadPosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return { x = left, y = top }
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Name(CARROT, L["CARROT_TITLE"]), 1, 1, 1)
    if preview or windowPreview then
        GameTooltip:AddLine(L["CARROT_PREVIEW"], 1, 0.82, 0, true)
    elseif self.state == "swap" then
        GameTooltip:AddLine(L["CARROT_SWAP"], 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(string.format(L["CARROT_PUT_ON"], CR.ChosenSlot()), 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function Create()
    frame = CreateFrame("Frame", "Bulwark_Carrot", UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:Hide()

    local b = CreateFrame("Button", "Bulwark_CarrotTile", frame)
    b:SetAllPoints()
    b:RegisterForClicks("LeftButtonUp")
    pcall(b.SetPassThroughButtons, b, "RightButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    local okI, icon = pcall(C_Item.GetItemIconByID, CARROT)
    b.icon:SetTexture((okI and icon) or FALLBACK_ICON)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -6, 6)
    b.border:SetPoint("BOTTOMRIGHT", 6, -6)
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        if preview or windowPreview then return end
        if self.state == "puton" then CR.PutOn()
        elseif self.state == "swap" then CR.OpenSwap(self) end
    end)
    tile = b
    RestorePosition()
end

local function Show(state)
    tile.state = state
    local c = state == "swap" and COLOR_SWAP or COLOR_ON
    tile.border:SetVertexColor(c[1], c[2], c[3])
    frame:Show()
end

local function Hide()
    if frame then frame:Hide() end
    if tile and NS.Kit.IsListOpen(tile) then NS.Kit.CloseList() end
end

-- Mounted (or flying a taxi) clears the timer; the first moment on foot starts it.
local function TrackMount()
    if Mounted() or OnTaxi() then
        onFootSince = nil
    elseif not onFootSince then
        onFootSince = GetTime()
        C_Timer.After(DELAY + 0.1, function() CR.Queue() end)
    end
end

function CR:Refresh()
    if not frame then return end
    frame:SetScale(cfg().scale or 1)
    TrackMount()
    if preview or windowPreview then
        Show("puton")
        return
    end
    local state = CR.State()
    if state then
        Show(state)
    else
        Hide()
    end
end

function CR.Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        CR:Refresh()
    end)
end

-- /bwk audit carrot
function CR.Status()
    local state, why = CR.State()
    if state then
        NS:Print(L["CARROT_STATUS_" .. state], CR.CarrotSlot() or CR.ChosenSlot())
    else
        NS:Print(L["CARROT_STATUS_HIDDEN"], L["CARROT_BLOCK_" .. (why or "none")])
    end
end

function CR:SetWindowPreview(enabled)
    windowPreview = enabled and true or false
    CR.Queue()
end

function CR:ResetPosition()
    cfg().carrotPoint = nil
    if frame then RestorePosition() end
end

function CR:Changed() CR.Queue() end

function CR:GetFrames() return frame, tile end   -- tests

-- =========================================================================
-- Events
-- =========================================================================

local events = CreateFrame("Frame", "Bulwark_CarrotEvents")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        if not preview and not windowPreview then Hide() end
        return
    end
    if event == "UNIT_AURA" and unit ~= "player" then return end
    CR.Queue()
end)

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_MOUNT_DISPLAY_CHANGED",
                 "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_CONTROL_GAINED",
                 "PLAYER_CONTROL_LOST", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }

function CR:OnEnable()
    if not frame then Create() end
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    CR.Queue()
end

function CR:OnDisable()
    events:UnregisterAllEvents()
    Hide()
end

-- Blizzard's HUD Edit Mode: a sample tile so it can be placed; moves wait for Blizzard's Save.
NS.EditMode:Register({
    label = L["EDITMODE_CARROT"],
    GetFrame = function() return frame end,
    IsAvailable = function() return frame ~= nil and NS:IsAreaRunning("audit") and cfg().carrot and frame:IsShown() end,
    Read = function() return ReadPosition() end,
    Save = function(pos) if pos then cfg().carrotPoint = pos end end,
    Restore = function() if frame then RestorePosition() end end,
    OnEnter = function()
        if not frame or not NS:IsAreaRunning("audit") or not cfg().carrot then return end
        preview = true
        CR:Refresh()
    end,
    OnExit = function()
        if not preview then return end
        preview = false
        CR:Refresh()
    end,
})
