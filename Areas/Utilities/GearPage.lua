local ADDON_NAME, NS = ...
local L, Kit, Avoidance, Gear, Enchants, AH = NS.L, NS.Kit, NS.Avoidance, NS.GearAudit, NS.Enchants, NS.AuctionHouse
local C = Kit.C

-- Gear page: paperdoll of the chosen set with enchant verdicts (kb/addons/Bulwark-Utilities.md "Idea: Gear audit").
-- Red = no enchant, yellow = a different enchant adds more total avoidance (Avoidance sets only). Right-click marks a
-- flagged slot as intentional for this set. Suggestions are ranked by avoidance gain, not Best-in-Slot.

local STATE_COLOR = {
    missing = { 0.90, 0.20, 0.18, 1 },
    weaker = { 1.00, 0.80, 0.15, 1 },
    intentional = { 0.45, 0.52, 0.62, 1 },
}
local GOOD = { 0.30, 0.85, 0.45, 1 }
local SLOT_SIZE, SLOT_STEP = 34, 37
local DOLL_W = 250
local PANEL_X = 266

local SLOT_NAMES = {
    [1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT", [7] = "LEGSSLOT",
    [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [11] = "FINGER0SLOT", [12] = "FINGER1SLOT",
    [13] = "TRINKET0SLOT", [14] = "TRINKET1SLOT", [15] = "BACKSLOT", [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT",
}

local function cfg() return NS.db.utilities end

local function EmptyIcon(slot)
    local api = C_PaperDollInfo
    if api and api.GetInventorySlotInfo and SLOT_NAMES[slot] then
        local ok, _, tex = pcall(api.GetInventorySlotInfo, SLOT_NAMES[slot])
        if ok and tex then return tex end
    end
    return 136509   -- Interface\PaperDoll\UI-Backpack-EmptySlot
end

local function Gain(v) return string.format("%+.2f%%", v) end

-- One line per ranked entry for the tooltip: "Superior Deflection  +0.36% avoidance, +0 Sta".
local function EntryLine(entry)
    local sta = entry.stamina ~= 0 and string.format(L["GEAR_STA"], entry.stamina) or ""
    return string.format(L["GEAR_ENTRY"], Gear.EntryName(entry), Gain(entry.gain), sta)
end

local function ShowSlotTooltip(button)
    local page, slot = button.page, button.slot
    local r = page.audit and page.audit.slots[slot]
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local item = r and r.item
    local shown = false
    if item and item.where == "worn" and page.set and page.set.worn and GameTooltip.SetInventoryItem then
        shown = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", slot)
    end
    if not shown and item and item.link then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
    end
    if not shown and item and item.itemID and GameTooltip.SetItemByID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, item.itemID)
    end
    if not shown then GameTooltip:SetText(L["GEAR_EMPTY_SLOT"], 1, 1, 1) end

    local state = r and r.state
    if state then GameTooltip:AddLine(" ") end
    local best = r and r.list and r.list[1]
    if state == "missing" then
        GameTooltip:AddLine(L["GEAR_TIP_MISSING"], unpack(STATE_COLOR.missing))
        if best and best.gain > 0.005 then GameTooltip:AddLine(string.format(L["GEAR_TIP_BEST"], EntryLine(best)), 1, 1, 1, true) end
        GameTooltip:AddLine(L["GEAR_TIP_MARK"], C.muted[1], C.muted[2], C.muted[3], true)
    elseif state == "weaker" then
        GameTooltip:AddLine(L["GEAR_TIP_WEAKER"], unpack(STATE_COLOR.weaker))
        GameTooltip:AddLine(string.format(L["GEAR_TIP_BETTER"], EntryLine(best)), 1, 1, 1, true)
        GameTooltip:AddLine(L["GEAR_TIP_MARK"], C.muted[1], C.muted[2], C.muted[3], true)
    elseif state == "intentional" then
        GameTooltip:AddLine(L["GEAR_TIP_INTENTIONAL"], unpack(STATE_COLOR.intentional))
    elseif state == "unknown" then
        GameTooltip:AddLine(item.where == "bank" and L["GEAR_TIP_BANK"] or L["GEAR_TIP_NOT_FOUND"], C.warn[1], C.warn[2], C.warn[3], true)
    elseif state == "ok" then
        GameTooltip:AddLine(L["GEAR_TIP_OK"], GOOD[1], GOOD[2], GOOD[3], true)
    end
    GameTooltip:Show()
end

local function SlotButton(page, parent, slot)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    b.page, b.slot = page, slot
    b.edge = Kit.Fill(b, C.panel)                   -- 2 px frame around the icon: the state colour
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.selected = Kit.Border(b, { 1, 1, 1, 0 }, "OVERLAY")    -- white outline: the slot open in the picker
    b.pickMark = b:CreateTexture(nil, "OVERLAY")              -- gold corner: an enchant is on the list
    b.pickMark:SetSize(8, 8)
    b.pickMark:SetPoint("TOPRIGHT", -3, -3)
    b.pickMark:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    b.pickMark:Hide()
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", ShowSlotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        if not page.set then return end
        local r = page.audit and page.audit.slots[slot]
        if button == "LeftButton" then
            page.pickSlot = (page.pickSlot ~= slot and r and r.list and #r.list > 0) and slot or nil
            page.pickOffset = 0
            page:refresh()
            return
        end
        if not (r and (r.state == "missing" or r.state == "weaker" or r.state == "intentional")) then return end
        local marks = Gear.Config(page.set.key).intentional
        marks[slot] = not marks[slot] or nil
        page:refresh()
        if GameTooltip:IsOwned(self) then ShowSlotTooltip(self) end
    end)
    return b
end

local function SetSlot(b, r)
    local item = r and r.item
    local icon = item and ((r.info and r.info.icon) or (item.link and select(5, C_Item.GetItemInfoInstant(item.link)))
        or (item.itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemID)))
    b.icon:SetTexture(icon or EmptyIcon(b.slot))
    b.icon:SetDesaturated(not icon or (r and r.state == "unknown") or false)
    b.icon:SetAlpha(icon and 1 or 0.5)
    local c = r and STATE_COLOR[r.state] or C.panel
    b.edge:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- Toggle-style button (gold border + lit background when selected).
local function Toggle(parent, text, width, onClick)
    local b = Kit.Button(parent, text, width, onClick)
    function b:SetSelected(on)
        self.selected = on
        self.bg:SetColorTexture(unpack(on and C.buttonHover or C.button))
        Kit.SetBorderColor(self.edges, on and C.gold or C.goldDim)
    end
    b:HookScript("OnLeave", function(self) if self.selected then self:SetSelected(true) end end)
    return b
end

local function SetName(set)
    if set.current then return L["GEAR_CURRENT"] end
    return set.worn and string.format(L["GEAR_SET_WORN"], set.name) or set.name
end

---------------------------------------------------------------------------------------------------------------
-- Picker: the enchants that fit one slot; ticking one puts it on the enchant list (one per slot per set)
---------------------------------------------------------------------------------------------------------------

local PICK_ROWS, ROW_H = 7, 20
local COL_GAIN, COL_STA = 268, 336

-- What one enchant costs with Auctionator's prices: the item that applies it, or all its mats ({ item, n } list).
local function SourceCostList(src)
    if src.item then return { { item = src.item, n = 1 } } end
    local list = {}
    for i = 1, #(src.reagents or {}), 2 do list[#list + 1] = { item = src.reagents[i], n = src.reagents[i + 1] } end
    return list
end

-- "Cost: 4g 20s" (+ "2 without a price"); nothing without Auctionator.
local function AddCost(src)
    if not AH.Available() then return end
    local total, unknown = AH.Cost(SourceCostList(src))
    local text
    if total > 0 then
        text = string.format(L["AH_COST"], AH.Money(total))
        if unknown > 0 then text = text .. "  " .. string.format(L["AH_UNPRICED"], unknown) end
    else
        text = L["AH_NO_PRICE"]
    end
    GameTooltip:AddLine(text, C.muted[1], C.muted[2], C.muted[3], true)
end

local function AddMats(src)
    if src.item then
        GameTooltip:AddLine(L["PICK_TIP_ITEM"], C.muted[1], C.muted[2], C.muted[3], true)
        AddCost(src)
        return
    end
    GameTooltip:AddLine(L["PICK_TIP_MATS"], C.goldText[1], C.goldText[2], C.goldText[3])
    for i = 1, #(src.reagents or {}), 2 do
        local id, n = src.reagents[i], src.reagents[i + 1]
        local have = Gear.Have(id)
        local c = have >= n and GOOD or C.text
        GameTooltip:AddDoubleLine(string.format("%dx %s", n, Gear.ItemName(id) or ("#" .. id)),
            string.format(L["PICK_HAVE"], have), 1, 1, 1, c[1], c[2], c[3])
    end
    AddCost(src)
end

local function ShowRowTooltip(row)
    local e = row.entry
    if not e then return end
    local src = e.sources[1]
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if not (src.item and GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, src.item)) then
        GameTooltip:SetText(Gear.EntryName(e), 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if e.current then
        GameTooltip:AddLine(L["PICK_TIP_CURRENT"], GOOD[1], GOOD[2], GOOD[3], true)
    else
        GameTooltip:AddLine(string.format(L["PICK_TIP_GAIN"], Gain(e.gain), e.stamina), 1, 1, 1, true)
    end
    if (Enchants.Stats(e.enchant).block or 0) > 0 and Enchants.IgnoresBlock((Avoidance:Get())) then
        GameTooltip:AddLine(L["PICK_TIP_NO_BLOCK"], C.muted[1], C.muted[2], C.muted[3], true)
    end
    if src.minIlvl then GameTooltip:AddLine(string.format(L["PICK_TIP_ILVL"], src.minIlvl), C.muted[1], C.muted[2], C.muted[3], true) end
    if src.reqLevel then GameTooltip:AddLine(string.format(L["PICK_TIP_LEVEL"], src.reqLevel), C.muted[1], C.muted[2], C.muted[3], true) end
    AddMats(src)
    if not e.current then
        GameTooltip:AddLine(row.picked and L["PICK_TIP_UNPICK"] or L["PICK_TIP_PICK"], C.muted[1], C.muted[2], C.muted[3], true)
    end
    GameTooltip:Show()
end

local function PickerRow(page, parent, i)
    local row = CreateFrame("Button", nil, parent)
    row.isPickRow = true
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 10, -54 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    row.hover = Kit.Fill(row, { 1, 1, 1, 0 })
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(12, 12)
    row.box:SetPoint("LEFT", 6, 0)
    row.tick = Kit.Fill(row.box, C.gold)
    Kit.Border(row.box, C.goldDim)
    row.name = Kit.Text(row, 12)
    row.name:SetPoint("LEFT", 24, 0)
    row.name:SetPoint("RIGHT", row, "LEFT", COL_GAIN - 70, 0)
    row.name:SetWordWrap(false)
    row.gain = Kit.Text(row, 12)
    row.gain:SetPoint("RIGHT", row, "LEFT", COL_GAIN, 0)
    row.sta = Kit.Text(row, 12)
    row.sta:SetPoint("RIGHT", row, "LEFT", COL_STA, 0)
    row:SetScript("OnEnter", function(self)
        self.hover:SetColorTexture(1, 1, 1, 0.05)
        ShowRowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e or e.current then return end
        Gear.SetPick(page.set.key, page.pickSlot, not self.picked and e.sources[1].spell or nil)
        page:refresh()
        if GameTooltip:IsOwned(self) then ShowRowTooltip(self) end
    end)
    return row
end

local function RefreshPicker(page, c)
    local r = page.pickSlot and page.audit.slots[page.pickSlot]
    local list = r and r.list
    if not (list and #list > 0) then
        page.pickSlot = nil
        page.picker:Hide()
        page.summary:Show()
        return
    end
    page.summary:Hide()
    page.picker:Show()
    Gear.SortFor(list, c.purpose, c.school)
    page.picker.title:SetText(string.format(L["PICK_TITLE"], L["SLOT_" .. page.pickSlot]))
    page.colGain:SetText(c.purpose == "resistance" and L["SCHOOL_" .. c.school] or L["PICK_COL_GAIN"])
    local maxOffset = math.max(0, #list - PICK_ROWS)
    page.pickOffset = math.min(page.pickOffset or 0, maxOffset)
    page.more:SetText(maxOffset > 0 and string.format(L["PICK_MORE"], page.pickOffset + 1,
        math.min(#list, page.pickOffset + PICK_ROWS), #list) or "")
    local picked = Gear.GetPick(page.set.key, page.pickSlot)
    for i, row in ipairs(page.rows) do
        local e = list[page.pickOffset + i]
        row.entry = e
        row:SetShown(e ~= nil)
        if e then
            row.picked = picked ~= nil and picked == e.sources[1].spell
            row.tick:SetShown(row.picked)
            row.box:SetShown(not e.current)
            local name = Gear.EntryName(e)
            row.name:SetText(e.current and string.format(L["PICK_CURRENT"], name) or name)
            Kit.SetTextColor(row.name, e.current and GOOD or (row.picked and C.goldText or C.text))
            if c.purpose == "resistance" then
                local res = Enchants.Stats(e.enchant)[c.school]
                row.gain:SetText(res and string.format("+%d", res) or "")
            else
                row.gain:SetText(e.current and "" or Gain(e.gain))
            end
            row.sta:SetText((e.current or e.stamina == 0) and "" or string.format("%+d", e.stamina))
        end
    end
    page.pickCount:SetText(string.format(L["PICK_LIST_COUNT"], Gear.OpenPicks()))
end

local function OpenList()
    if NS.Window and NS.Window.Select then NS.Window:Select("utilities", "enchantlist") end
end

NS:AddPage("utilities", {
    key = "gear",
    title = L["PAGE_GEAR"],
    before = "options",
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_GEAR"], L["GEAR_DESC"])
        page.selected = nil      -- key of the chosen set (nil = the worn one)

        -- Paperdoll: two slot columns with the character model between them.
        page.slots = {}
        for i, slot in ipairs(Gear.LEFT) do
            local b = SlotButton(page, parent, slot)
            b:SetPoint("TOPLEFT", 0, y - (i - 1) * SLOT_STEP)
            page.slots[slot] = b
        end
        for i, slot in ipairs(Gear.RIGHT) do
            local b = SlotButton(page, parent, slot)
            b:SetPoint("TOPLEFT", DOLL_W - SLOT_SIZE, y - (i - 1) * SLOT_STEP)
            page.slots[slot] = b
        end
        local doll = CreateFrame("Frame", nil, parent)
        doll:SetPoint("TOPLEFT", SLOT_SIZE + 6, y)
        doll:SetSize(DOLL_W - 2 * SLOT_SIZE - 12, 8 * SLOT_STEP - 3)
        Kit.Fill(doll, C.panel)
        Kit.Border(doll, C.cardBorder)
        local ok, model = pcall(CreateFrame, "PlayerModel", nil, doll)
        if ok and model then
            model:SetAllPoints()
            page.model = model
        end
        page.modelNote = Kit.Paragraph(doll, "", DOLL_W - 2 * SLOT_SIZE - 24, 10, C.muted)
        page.modelNote:SetPoint("BOTTOM", 0, 6)
        page.modelNote:SetJustifyH("CENTER")

        -- Set card: selector + purpose
        local set = Kit.Card(parent, L["CARD_GEAR_SET"])
        set:SetPoint("TOPLEFT", PANEL_X, y)
        set:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        set:SetHeight(132)
        page.prev = Kit.Button(set, "<", 26, function() page:step(-1) end)
        page.prev:SetPoint("TOPLEFT", 12, -40)
        page.next = Kit.Button(set, ">", 26, function() page:step(1) end)
        page.next:SetPoint("TOPRIGHT", -12, -40)
        page.setName = Kit.Text(set, 13, C.goldText)
        page.setName:SetPoint("LEFT", page.prev, "RIGHT", 8, 0)
        page.setName:SetPoint("RIGHT", page.next, "LEFT", -8, 0)
        page.setName:SetJustifyH("CENTER")
        page.purpose = {}
        for i, key in ipairs(Gear.PURPOSES) do
            local b = Toggle(set, L["PURPOSE_" .. key], 84, function()
                Gear.Config(page.set.key).purpose = key
                page:refresh()
            end)
            b:SetPoint("TOPLEFT", 12 + (i - 1) * 88, -74)
            Kit.Tooltip(b, L["PURPOSE_" .. key], L["PURPOSE_" .. key .. "_DESC"])
            page.purpose[key] = b
        end
        page.school = Kit.Button(set, "", 150, function()
            local c = Gear.Config(page.set.key)
            for i, s in ipairs(Gear.SCHOOLS) do
                if s == c.school then c.school = Gear.SCHOOLS[i % #Gear.SCHOOLS + 1]; break end
            end
            page:refresh()
        end)
        page.school:SetPoint("TOPLEFT", 12, -104)
        page.resist = Kit.Text(set, 12)
        page.resist:SetPoint("LEFT", page.school, "RIGHT", 12, 0)

        -- Summary card
        local sum = Kit.Card(parent, L["CARD_GEAR_SUMMARY"])
        sum:SetPoint("TOPLEFT", PANEL_X, y - 142)
        sum:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        sum:SetHeight(220)                              -- runs below the doll: the explanation wraps to 3 lines
        page.frozen = Kit.Text(sum, 11, C.warn)
        page.frozen:SetPoint("TOPRIGHT", -14, -14)
        page.explain = Kit.Paragraph(sum, "", 340, 11, C.muted)
        page.explain:SetPoint("TOPLEFT", 16, -40)
        page.goal1 = Kit.Text(sum, 12)
        page.goal1:SetPoint("TOPLEFT", 16, -84)
        page.goal2 = Kit.Text(sum, 12)
        page.goal2:SetPoint("TOPLEFT", 16, -102)
        page.counts = Kit.Text(sum, 12)
        page.counts:SetPoint("TOPLEFT", 16, -126)
        page.hint = Kit.Paragraph(sum, L["GEAR_HINT"], 340, 11, C.muted)
        page.hint:SetPoint("TOPLEFT", 16, -146)
        page.listCount = Kit.Text(sum, 12, C.goldText)
        page.listCount:SetPoint("BOTTOMLEFT", 16, 16)
        local listBtn = Kit.Button(sum, L["BTN_ENCHANT_LIST"], 120, OpenList)
        listBtn:SetPoint("BOTTOMRIGHT", -12, 10)
        page.summary = sum

        -- Picker card (replaces the summary while a slot is open)
        local picker = Kit.Card(parent, "")
        picker:SetPoint("TOPLEFT", PANEL_X, y - 142)
        picker:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        picker:SetHeight(232)
        picker:Hide()
        page.picker = picker
        local close = Kit.Button(picker, "x", 22, function()
            page.pickSlot = nil
            page:refresh()
        end)
        close:SetPoint("TOPRIGHT", -8, -6)
        local colName = Kit.Text(picker, 11, C.muted)
        colName:SetPoint("TOPLEFT", 40, -38)
        colName:SetText(L["PICK_COL_NAME"])
        page.colGain = Kit.Text(picker, 11, C.muted)
        page.colGain:SetPoint("TOPRIGHT", picker, "TOPLEFT", 10 + COL_GAIN, -38)
        local colSta = Kit.Text(picker, 11, C.muted)
        colSta:SetPoint("TOPRIGHT", picker, "TOPLEFT", 10 + COL_STA, -38)
        colSta:SetText(L["PICK_COL_STA"])
        page.rows = {}
        for i = 1, PICK_ROWS do page.rows[i] = PickerRow(page, picker, i) end
        picker:EnableMouseWheel(true)
        picker:SetScript("OnMouseWheel", function(_, delta)
            page.pickOffset = math.max(0, (page.pickOffset or 0) - delta)
            page:refresh()
        end)
        page.more = Kit.Text(picker, 11, C.muted)
        page.more:SetPoint("TOPRIGHT", -40, -14)
        page.pickCount = Kit.Text(picker, 12, C.goldText)
        page.pickCount:SetPoint("BOTTOMLEFT", 16, 16)
        local listBtn2 = Kit.Button(picker, L["BTN_ENCHANT_LIST"], 120, OpenList)
        listBtn2:SetPoint("BOTTOMRIGHT", -12, 10)

        -- Re-check when gear, sets, bags or stats change (shown page only; batched).
        local pending = false
        local function Later()
            if pending or not (page.frame and page.frame:IsShown()) then return end
            pending = true
            C_Timer.After(0.2, function()
                pending = false
                if page.frame and page.frame:IsShown() then
                    page:refresh()
                    -- A mat name loads after the tooltip was drawn ("#11176"): redraw it (GET_ITEM_INFO_RECEIVED).
                    local owner = GameTooltip:GetOwner()
                    if owner and owner.isPickRow and owner.entry and owner:IsVisible() then ShowRowTooltip(owner) end
                end
            end)
        end
        local events = CreateFrame("Frame")
        for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED",
                             "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "GET_ITEM_INFO_RECEIVED" }) do
            pcall(events.RegisterEvent, events, e)
        end
        events:SetScript("OnEvent", Later)
        NS:On("AVOIDANCE_CHANGED", Later)
        NS:On("GEAR_PICKS_CHANGED", Later)
    end,

    step = function(page, dir)
        page.pickSlot = nil
        local sets = Gear.Sets()
        local index = 1
        for i, s in ipairs(sets) do
            if s.key == (page.set and page.set.key) then index = i end
        end
        index = (index - 1 + dir) % #sets + 1
        page.selected = sets[index].key
        page:refresh()
    end,

    refresh = function(page)
        local sets = Gear.Sets()
        local set = sets[1]
        for _, s in ipairs(sets) do
            if s.key == page.selected then set = s end
        end
        page.set = set
        page.prev:SetActive(#sets > 1)
        page.next:SetActive(#sets > 1)
        page.setName:SetText(SetName(set))
        local c = Gear.Config(set.key)
        for key, b in pairs(page.purpose) do b:SetSelected(c.purpose == key) end
        page.school:SetShown(c.purpose == "resistance")
        page.school:SetLabel(string.format(L["GEAR_SCHOOL"], L["SCHOOL_" .. c.school]))

        if page.model then
            pcall(page.model.SetUnit, page.model, "player")
        end
        page.modelNote:SetText(set.worn and "" or L["GEAR_MODEL_NOTE"])

        local snap, frozen = Avoidance:Get()
        page.frozen:SetText(frozen and snap and L["AV_FROZEN"] or "")
        local opts = { offset = cfg().mobOffset }
        page.audit = Gear.Audit(set, snap, opts)
        for slot, b in pairs(page.slots) do
            SetSlot(b, page.audit.slots[slot])
            Kit.SetBorderColor(b.selected, { 1, 1, 1, page.pickSlot == slot and 1 or 0 })
            b.pickMark:SetShown(Gear.GetPick(set.key, slot) ~= nil)
        end
        RefreshPicker(page, c)
        page.listCount:SetText(string.format(L["PICK_LIST_COUNT"], Gear.OpenPicks()))

        -- Resistance line (worn sets only: UnitResistance reads what is worn)
        page.resist:SetText("")
        if c.purpose == "resistance" and set.worn then
            local ok, _, total = pcall(UnitResistance, "player", Gear.SCHOOL_INDEX[c.school])   -- base, total, ...
            if ok and type(total) == "number" then
                page.resist:SetText(string.format(L["GEAR_RESIST"], L["SCHOOL_" .. c.school], total))
            end
        end

        -- Summary
        local mob = (snap and snap.level or UnitLevel("player") or 60) + opts.offset
        page.explain:SetText(string.format(L["GEAR_EXPLAIN_" .. c.purpose], mob))
        page.goal1:SetText(""); page.goal2:SetText("")
        if not snap then
            page.goal1:SetText(L["AV_NO_DATA"])
            Kit.SetTextColor(page.goal1, C.muted)
        elseif c.purpose == "avoidance" then
            if set.worn then
                local r = Avoidance.Compute(snap, opts)
                if r.critImmune then
                    local spare = math.floor(snap.defense - (r.mobLevel * 5 + 5 / 0.04))
                    page.goal1:SetText(string.format(L["GEAR_GOAL_CRIT_OK"], r.mobLevel, spare))
                    Kit.SetTextColor(page.goal1, GOOD)
                else
                    page.goal1:SetText(string.format(L["GEAR_GOAL_CRIT_SHORT"], r.mobLevel, r.defenseNeeded))
                    Kit.SetTextColor(page.goal1, C.warn)
                end
                if not r.canCrush then
                    page.goal2:SetText(string.format(L["VERDICT_NO_CRUSH"], r.mobLevel))
                    Kit.SetTextColor(page.goal2, C.muted)
                elseif r.uncrushable then
                    page.goal2:SetText(string.format(L["GEAR_GOAL_CRUSH_OK"], Gain(r.total - 100)))
                    Kit.SetTextColor(page.goal2, GOOD)
                else
                    page.goal2:SetText(string.format(L["GEAR_GOAL_CRUSH_SHORT"], string.format("%.2f%%", r.short)))
                    Kit.SetTextColor(page.goal2, C.warn)
                end
            else
                page.goal1:SetText(L["GEAR_GOAL_EQUIP"])
                Kit.SetTextColor(page.goal1, C.muted)
            end
        end
        local n = page.audit.counts
        if c.purpose == "none" then
            page.counts:SetText("")
        elseif n.missing + n.weaker == 0 then
            page.counts:SetText(L["GEAR_ALL_GOOD"])
            Kit.SetTextColor(page.counts, GOOD)
        else
            page.counts:SetText(string.format(L["GEAR_COUNTS"], n.missing, n.weaker))
            Kit.SetTextColor(page.counts, C.text)
        end
        if n.intentional > 0 then
            page.counts:SetText(page.counts:GetText() .. "  " .. string.format(L["GEAR_COUNT_INTENTIONAL"], n.intentional))
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Enchant list: what was ticked on the Gear page, and the mats still needed (bags + bank)
---------------------------------------------------------------------------------------------------------------

local LIST_ROWS, MAT_ROWS = 5, 7        -- 5 pick rows: the page must fit the window with the Auctionator footer ([in-game])
local HEADER_H = 18          -- column header line above the mats rows (Auctionator only)

local function SetLabel(key)
    if key == Gear.WORN then return L["GEAR_CURRENT_SHORT"] end
    return key
end

-- Rows with mouse-wheel scrolling: rows[i] filled by fill(row, data[offset + i]).
local function ScrollRows(card, count, y, make)
    local list = { rows = {}, offset = 0 }
    for i = 1, count do
        local row = make(card)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 10, y - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        list.rows[i] = row
    end
    list.more = Kit.Text(card, 11, C.muted)
    list.more:SetPoint("TOPRIGHT", -14, -14)
    card:EnableMouseWheel(true)
    card:SetScript("OnMouseWheel", function(_, delta)
        list.offset = math.max(0, list.offset - delta)
        if list.redraw then list.redraw() end
    end)
    function list:Show(data, fill)
        self.redraw = function() self:Show(data, fill) end
        local maxOffset = math.max(0, #data - count)
        self.offset = math.min(self.offset, maxOffset)
        self.more:SetText(maxOffset > 0 and string.format(L["PICK_MORE"], self.offset + 1,
            math.min(#data, self.offset + count), #data) or "")
        for i, row in ipairs(self.rows) do
            local d = data[self.offset + i]
            row.data = d
            row:SetShown(d ~= nil)
            if d then fill(row, d) end
        end
    end
    return list
end

local function TextRow(card, withRemove)
    local row = CreateFrame("Button", nil, card)
    row.hover = Kit.Fill(row, { 1, 1, 1, 0 })
    row.left = Kit.Text(row, 12)
    row.left:SetPoint("LEFT", 6, 0)
    row.left:SetPoint("RIGHT", row, "RIGHT", withRemove and -150 or -250, 0)
    row.left:SetWordWrap(false)
    row.right = Kit.Text(row, 12)
    row.right:SetPoint("RIGHT", withRemove and -34 or -6, 0)
    if not withRemove then
        row.price = Kit.Text(row, 12)                -- mats: cost of the missing ones (Auctionator only)
        row.price:SetPoint("RIGHT", -90, 0)
    end
    row:SetScript("OnEnter", function(self)
        self.hover:SetColorTexture(1, 1, 1, 0.05)
        if self.tooltip then self.tooltip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    if withRemove then
        row.remove = Kit.Button(row, "x", 20, function() if row.onRemove then row.onRemove() end end)
        row.remove:SetHeight(18)
        row.remove:SetPoint("RIGHT", -4, 0)
    end
    return row
end

local function PickName(src)
    return Gear.EntryName({ enchant = src.enchant, sources = { src } })
end

NS:AddPage("utilities", {
    key = "enchantlist",
    title = L["PAGE_ENCHANT_LIST"],
    before = "options",
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_ENCHANT_LIST"], L["ENCHANT_LIST_DESC"])
        y = y + 8                                    -- the one-line description leaves room: tighter, so both cards fit
        local picks = Kit.Card(parent, L["CARD_PICKED"])
        picks:SetPoint("TOPLEFT", 0, y)
        picks:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        picks:SetHeight(44 + LIST_ROWS * ROW_H + 8)
        page.picks = ScrollRows(picks, LIST_ROWS, -38, function(card) return TextRow(card, true) end)
        page.empty = Kit.Paragraph(picks, L["ENCHANT_LIST_EMPTY"], 600, 12, C.muted)
        page.empty:SetPoint("TOPLEFT", 16, -42)
        page.clear = Kit.Button(picks, L["BTN_CLEAR_LIST"], 110, function()
            Gear.ClearPicks()
            page:refresh()
        end)
        page.clear:SetHeight(20)                    -- fits above the title line ([in-game] 24 px crossed it)
        page.clear:SetPoint("TOPRIGHT", -14, -5)
        page.picks.more:ClearAllPoints()
        page.picks.more:SetPoint("RIGHT", page.clear, "LEFT", -12, 0)

        local matsY = y - (44 + LIST_ROWS * ROW_H + 8) - 10
        local mats = Kit.Card(parent, L["CARD_MATS"])
        mats:SetPoint("TOPLEFT", 0, matsY)
        mats:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        mats:SetHeight(44 + MAT_ROWS * ROW_H + 8)
        page.matsCard = mats
        page.mats = ScrollRows(mats, MAT_ROWS, -38, function(card) return TextRow(card, false) end)
        -- Auctionator footer (only while Auctionator is loaded): cost of what's missing + shopping list button.
        -- Column headers on their own line (the rows move down under them; [in-game] squeezed above row 1 otherwise)
        page.colPrice = Kit.Text(mats, 11, C.muted)
        page.colPrice:SetPoint("TOPRIGHT", -100, -40)
        page.colPrice:SetText(L["AH_COL_PRICE"])
        page.colHave = Kit.Text(mats, 11, C.muted)
        page.colHave:SetPoint("TOPRIGHT", -16, -40)
        page.colHave:SetText(L["AH_COL_HAVE"])
        page.total = Kit.Text(mats, 12, C.goldText)
        page.total:SetPoint("BOTTOMLEFT", 16, 14)
        page.send = Kit.Button(mats, L["BTN_SEND_AUCTIONATOR"], 160, function() page:sendList() end)
        page.send:SetHeight(20)
        page.send:SetPoint("BOTTOMRIGHT", -14, 10)
        Kit.Tooltip(page.send, L["BTN_SEND_AUCTIONATOR"], string.format(L["AH_SEND_DESC"], AH.LIST_NAME))
        page.matsNote = Kit.Text(mats, 12, C.muted)
        page.matsNote:SetPoint("TOPLEFT", 16, -42)
        page.track = Kit.Button(mats, "", 130, function()
            NS.MatsTracker:SetShown(not NS.char.gear.tracker.shown)
            page:refresh()
        end)
        page.track:SetHeight(20)
        page.track:SetPoint("TOPRIGHT", -14, -5)
        Kit.Tooltip(page.track, L["TRACKER_TITLE"], L["TRACKER_DESC"])
        page.mats.more:ClearAllPoints()
        page.mats.more:SetPoint("RIGHT", page.track, "LEFT", -12, 0)

        local pending = false
        local function Later()
            if pending or not (page.frame and page.frame:IsShown()) then return end
            pending = true
            C_Timer.After(0.2, function()
                pending = false
                if page.frame and page.frame:IsShown() then page:refresh() end
            end)
        end
        local events = CreateFrame("Frame")
        for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "GET_ITEM_INFO_RECEIVED",
                             "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED" }) do
            pcall(events.RegisterEvent, events, e)
        end
        events:SetScript("OnEvent", Later)
        NS:On("GEAR_PICKS_CHANGED", Later)
    end,

    refresh = function(page)
        local picks, mats = Gear.ShoppingList()
        page.empty:SetShown(#picks == 0)
        page.clear:SetShown(#picks > 0)
        page.picks:Show(picks, function(row, p)
            local name = PickName(p.src)
            row.left:SetText(string.format(L["LIST_PICK"], SetLabel(p.set), L["SLOT_" .. p.slot], name))
            Kit.SetTextColor(row.left, p.done and C.muted or C.text)
            row.right:SetText(p.done and L["LIST_DONE"] or "")
            Kit.SetTextColor(row.right, GOOD)
            row.onRemove = function() Gear.SetPick(p.set, p.slot, nil); page:refresh() end
            row.tooltip = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(name, 1, 1, 1)
                AddMats(p.src)
                GameTooltip:Show()
            end
        end)
        page.matsNote:SetText(#mats == 0 and (#picks > 0 and L["MATS_ALL_DONE"] or "") or "")
        page.track:SetLabel(NS.char.gear.tracker.shown and L["BTN_TRACK_HIDE"] or L["BTN_TRACK_SHOW"])
        local priced = AH.Available()
        page.mats:Show(mats, function(row, m)
            local have = Gear.Have(m.item)
            local missing = math.max(0, m.need - have)
            row.left:SetText(Gear.ItemName(m.item) or ("#" .. m.item))
            row.right:SetText(string.format(L["MATS_HAVE_NEED"], math.min(have, m.need), m.need))
            local enough = missing == 0
            Kit.SetTextColor(row.left, enough and C.muted or C.text)
            Kit.SetTextColor(row.right, enough and GOOD or C.warn)
            local unit, source = nil, nil
            if priced then unit, source = AH.Price(m.item) end
            row.price:SetText((priced and missing > 0) and (unit and AH.Money(unit * missing) or L["AH_NO_PRICE_SHORT"]) or "")
            Kit.SetTextColor(row.price, unit and C.text or C.muted)
            row.tooltip = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if not (GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, m.item)) then
                    GameTooltip:SetText(row.left:GetText(), 1, 1, 1)
                end
                GameTooltip:AddLine(string.format(L["PICK_HAVE"], have), 1, 1, 1)
                if priced then
                    if unit and source == "vendor" then
                        GameTooltip:AddLine(string.format(L["AH_TIP_VENDOR"], AH.Money(unit)), C.muted[1], C.muted[2], C.muted[3], true)
                    elseif unit then
                        local age = AH.Age(m.item)
                        local seen = age == 0 and L["AH_SEEN_TODAY"] or (age and string.format(L["AH_SEEN_DAYS"], age)) or ""
                        GameTooltip:AddLine(string.format(L["AH_TIP_AUCTION"], AH.Money(unit), seen), C.muted[1], C.muted[2], C.muted[3], true)
                    else
                        GameTooltip:AddLine(L["AH_TIP_NONE"], C.muted[1], C.muted[2], C.muted[3], true)
                    end
                end
                GameTooltip:Show()
            end
        end)

        -- Auctionator footer
        local header = (priced and #mats > 0) and HEADER_H or 0
        page.matsCard:SetHeight(44 + MAT_ROWS * ROW_H + 8 + (priced and 30 or 0) + header)
        for i, r in ipairs(page.mats.rows) do
            r:ClearAllPoints()
            r:SetPoint("RIGHT", page.matsCard, "RIGHT", -10, 0)
            r:SetPoint("TOPLEFT", 10, -38 - header - (i - 1) * ROW_H)
        end
        page.colPrice:SetShown(header > 0)
        page.colHave:SetShown(header > 0)
        page.total:SetShown(priced)
        page.send:SetShown(priced and AH.CanSend())
        if priced then
            local buy = page:toBuy(mats)
            local total, unknown = AH.Cost(buy)
            local text
            if #buy == 0 then
                text = #mats > 0 and L["AH_NOTHING_TO_BUY"] or ""
            elseif total > 0 then
                text = string.format(L["AH_TOTAL"], AH.Money(total))
                if unknown > 0 then text = text .. "  " .. string.format(L["AH_UNPRICED"], unknown) end
            else
                text = L["AH_NO_PRICE"]
            end
            page.total:SetText(text)
            page.send:SetActive(#buy > 0)
        end
    end,

    -- The mats still missing: { { item, n = need - have } }, only those with n > 0.
    toBuy = function(_, mats)
        local list = {}
        for _, m in ipairs(mats) do
            local n = m.need - Gear.Have(m.item)
            if n > 0 then list[#list + 1] = { item = m.item, n = n } end
        end
        return list
    end,

    sendList = function(page)
        local _, mats = Gear.ShoppingList()
        local sent, skipped = AH.SendList(page:toBuy(mats), Gear.ItemName)
        if not sent then
            NS:Print(L["AH_SEND_FAILED"])
        elseif sent == 0 then
            NS:Print(skipped > 0 and L["AH_SEND_NOT_LOADED"] or L["AH_NOTHING_TO_BUY"])
        else
            NS:Print(string.format(L["AH_SENT"], sent, AH.LIST_NAME)
                .. (skipped > 0 and (" " .. string.format(L["AH_SENT_SKIPPED"], skipped)) or ""))
        end
    end,
})
