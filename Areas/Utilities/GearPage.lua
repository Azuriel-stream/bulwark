local ADDON_NAME, NS = ...
local L, Kit, Avoidance, Gear = NS.L, NS.Kit, NS.Avoidance, NS.GearAudit
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
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", ShowSlotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" or not page.set then return end
        local r = page.audit and page.audit.slots[slot]
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

        -- Re-check when gear, sets, bags or stats change (shown page only; batched).
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
        for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED",
                             "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "GET_ITEM_INFO_RECEIVED" }) do
            pcall(events.RegisterEvent, events, e)
        end
        events:SetScript("OnEvent", Later)
        NS:On("AVOIDANCE_CHANGED", Later)
    end,

    step = function(page, dir)
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
        for slot, b in pairs(page.slots) do SetSlot(b, page.audit.slots[slot]) end

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
