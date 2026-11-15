local ADDON_NAME, NS = ...
local Kit, MK = NS.Kit, NS.Marking
local L, Utils = MK.L, MK.Utils
local C = Kit.C

-- Marking: pre-pull pack planner, one-key marking, team setup, mob database and HUD (from TankMarkForever).
-- Pages replace TankMark's setup and mob windows (UI/Setup.lua, UI/Mobs.lua); the commands its /tmf.
local area = NS:RegisterArea({
    key = "marking",
    order = 3,
    title = NS.L["AREA_MARKING"],
    desc = NS.L["AREA_MARKING_DESC"],
    icon = "tab_marking",
    legacy = "TankMarkForever",
})

local function Card(parent, title, y, height)
    local card = Kit.Card(parent, title)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card:SetHeight(height)
    return card
end

local function Note(parent, text, x, y, width)
    local fs = Kit.Paragraph(parent, text, width or 560, 11, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    return fs
end

-- Repaints a page when the setup or the database changes, if it's built and on screen.
local function RefreshIfShown(page)
    if page.frame and page.frame:IsShown() and page.refresh then page:refresh() end
end

---------------------------------------------------------------------------------------------------------------
-- Team (kill order, roles, players): from TankMarkForever UI/Setup.lua
---------------------------------------------------------------------------------------------------------------

local ROW_H = 32

-- Player list for a Team row: none, then the group (class coloured); a saved player who left stays listed, grey.
local function PlayerOptions(i)
    local row = MK.Team:Rows()[i]
    local opts = { { key = "", label = row.role == "TANK" and L["SETUP_ANYONE"] or L["SETUP_NOBODY"] } }
    local listed = false
    for _, m in ipairs(MK.Team:Members()) do
        opts[#opts + 1] = { key = m.name, label = Utils.ClassColored(m.short, m.class) }
        if m.name == row.player then listed = true end
    end
    if row.player and not listed then
        opts[#opts + 1] = { key = row.player, label = "|cff888888" .. row.player .. "|r" }
    end
    return opts
end

local teamPage = NS:AddPage(area.key, {
    key = "team",
    title = NS.L["PAGE_TEAM"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, NS.L["PAGE_TEAM"], L["SETUP_HEADER"])
        local card = Card(parent, nil, y, 8 * ROW_H + 20)
        page.rows = {}
        for i = 1, 8 do
            local row = CreateFrame("Frame", nil, card)
            row:SetSize(600, ROW_H)
            row:SetPoint("TOPLEFT", 12, -10 - (i - 1) * ROW_H)
            row.order = Kit.Text(row, 13, C.goldText)
            row.order:SetPoint("LEFT", 4, 0)
            row.order:SetWidth(18)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", 28, 0)
            row.icon:SetTexture(Utils.ICON_TEXTURE)
            row.role = Kit.Button(row, "", 90, function() MK.Team:CycleRole(i) end)
            row.role:SetPoint("LEFT", 60, 0)
            Kit.Tooltip(row.role, L["SETUP_ROLE"], L["SETUP_ROLE_DESC"])
            -- Player: pick from the group (user 2026-11-14: was click-to-cycle, up to 40 clicks in a raid)
            row.player = Kit.AttachList(Kit.Button(row, "", 200), function() return PlayerOptions(i) end,
                function() return MK.Team:Rows()[i].player or "" end,
                function(name) MK.Team:SetPlayer(i, name ~= "" and name or nil) end, 220,
                function() MK.Team:ClearPlayer(i) end)
            row.player:SetPoint("LEFT", row.role, "RIGHT", 8, 0)
            Kit.Tooltip(row.player, L["SETUP_PLAYER"], L["SETUP_PLAYER_DESC"])
            row.up = Kit.Button(row, L["BTN_UP"], 56, function() MK.Team:MoveRow(i, -1) end)
            row.up:SetPoint("LEFT", row.player, "RIGHT", 8, 0)
            row.down = Kit.Button(row, L["BTN_DOWN"], 56, function() MK.Team:MoveRow(i, 1) end)
            row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
            page.rows[i] = row
        end
        local by = y - (8 * ROW_H + 20) - 12
        local announce = Kit.Button(parent, L["BTN_ANNOUNCE"], 130, function() MK.Team:Announce() end)
        announce:SetPoint("TOPLEFT", 0, by)
        Kit.Tooltip(announce, L["BTN_ANNOUNCE"], L["BTN_ANNOUNCE_DESC"])
        local reset = Kit.Button(parent, L["BTN_RESET"], 100, function() MK.Team:Reset() end)
        reset:SetPoint("LEFT", announce, "RIGHT", 10, 0)
        Kit.Tooltip(reset, L["BTN_RESET"], NS.L["MARK_RESET_TIP"])
    end,
    refresh = function(page)
        local rows = MK.Team:Rows()
        local killN = 0
        for i, r in ipairs(page.rows) do
            local data = rows[i]
            r.icon:SetTexCoord(Utils.IconTexCoord(data.icon))
            r.icon:SetDesaturated(data.off and true or false)
            r.icon:SetAlpha(data.off and 0.4 or 1)
            r.role:SetLabel(L["ROLE_" .. data.role] .. (data.off and (" " .. L["HUD_OFF"]) or ""))
            if data.role == "TANK" and not data.off then
                killN = killN + 1
                r.order:SetText(tostring(killN))
            else
                r.order:SetText("")
            end
            local text
            if data.player then
                local m = MK.Team:FindMember(data.player)
                text = m and Utils.ClassColored(m.short, m.class) or ("|cff888888" .. data.player .. "|r")
                if m and data.role == "CC" and not MK.Rules.HasCC(m.class) then
                    text = text .. " |cffff6060" .. L["SETUP_NO_CC"] .. "|r"
                end
            else
                text = data.role == "TANK" and L["SETUP_ANYONE"] or ("|cffff6060" .. L["SETUP_NEEDS_PLAYER"] .. "|r")
            end
            r.player:SetLabel(text)
            r.up:SetActive(i > 1)
            r.down:SetActive(i < #rows)
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Mobs (database per zone): from TankMarkForever UI/Mobs.lua. Paged list; zone picked from our own dropdown (Kit.Dropdown) or stepped with arrows.
---------------------------------------------------------------------------------------------------------------

local MOB_ROWS = 10
local MOB_ROW_H = 30
local rowData = {}   -- plain table, not frame fields (unset frame fields aren't nil in wowsim)
local NONE = { entry = {}, key = "", kind = "" }
local function D(i) return rowData[i] or NONE end

local function ClassLabel(class)
    if not class then return L["MOBS_ANY"] end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
    if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
    return name
end

local function IconOptions()
    local opts = { { key = 0, label = L["MOBS_AUTO"] } }
    for icon = 8, 1, -1 do
        opts[#opts + 1] = { key = icon, label = L["ICON_" .. icon], icon = Utils.ICON_TEXTURE,
                            iconCoords = { Utils.IconTexCoord(icon) } }
    end
    return opts
end

local function ClassOptions()
    local opts = { { key = "", label = L["MOBS_ANY"] } }
    for _, class in ipairs(MK.MobDB.CC_CLASSES) do opts[#opts + 1] = { key = class, label = ClassLabel(class) } end
    return opts
end

local mobsPage
local function MobRow(parent, i)
    local page = mobsPage
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(620, MOB_ROW_H)
    row:SetPoint("TOPLEFT", 10, -40 - (i - 1) * MOB_ROW_H)

    row.kind = Kit.Text(row, 10, C.muted)
    row.kind:SetPoint("LEFT", 2, 0)
    row.kind:SetWidth(34)
    -- Name entries: plain text. Signature entries: an edit box for the player's label.
    row.label = Kit.Text(row, 12)
    row.label:SetPoint("LEFT", 40, 0)
    row.label:SetWidth(190)
    row.note = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.note:SetSize(184, 20)
    row.note:SetPoint("LEFT", 46, 0)
    row.note:SetAutoFocus(false)
    row.note:SetMaxLetters(40)
    row.note:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text == MK.MobDB.DefaultLabel(page.zone, D(i).key, D(i).entry) then text = "" end   -- unchanged default
        MK.MobDB:SetNote(D(i).entry, text)
        self:ClearFocus()
    end)
    row.note:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        page:refresh()
    end)
    row.note:SetScript("OnEnter", function(self)
        local data = rowData[i]
        if not data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(MK.MobDB.DescribeSig(data.key), 1, 1, 1)
        local names = MK.MobDB.DataNames(page.zone, data.key, data.entry)
        if names then
            GameTooltip:AddLine(L["MOBS_DATA_NAMES"], nil, nil, nil, true)
            for _, name in ipairs(names) do GameTooltip:AddLine("  " .. name, 1, 1, 1) end
        end
        GameTooltip:AddLine(L["MOBS_NOTE_DESC"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row.note:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.type = Kit.Button(row, "", 64, function() MK.MobDB:CycleType(D(i).entry) end)
    row.type:SetPoint("LEFT", 238, 0)
    Kit.Tooltip(row.type, L["SETUP_ROLE"], L["MOBS_TYPE_DESC"])
    row.minus = Kit.Button(row, "-", 24, function() MK.MobDB:StepPrio(D(i).entry, -1) end)
    row.minus:SetPoint("LEFT", row.type, "RIGHT", 6, 0)
    row.prio = Kit.Text(row, 12)
    row.prio:SetPoint("LEFT", row.minus, "RIGHT", 4, 0)
    row.prio:SetWidth(16)
    row.plus = Kit.Button(row, "+", 24, function() MK.MobDB:StepPrio(D(i).entry, 1) end)
    row.plus:SetPoint("LEFT", row.prio, "RIGHT", 4, 0)
    Kit.Tooltip(row.plus, "+", L["MOBS_PRIO_DESC"])
    -- Icon and CC class: picked from a list (user 2026-11-14: were click-to-cycle)
    row.icon = Kit.AttachList(Kit.Button(row, "", 56), IconOptions,
        function() return D(i).entry.icon or 0 end,
        function(icon) MK.MobDB:SetIcon(D(i).entry, icon ~= 0 and icon or nil) end, 130,
        function() MK.MobDB:ClearIcon(D(i).entry) end)
    row.icon:SetPoint("LEFT", row.plus, "RIGHT", 6, 0)
    row.iconTex = row.icon:CreateTexture(nil, "OVERLAY")
    row.iconTex:SetSize(18, 18)
    row.iconTex:SetPoint("CENTER", -6, 0)
    row.iconTex:SetTexture(Utils.ICON_TEXTURE)
    Kit.Tooltip(row.icon, L["MOBS_AUTO"], L["MOBS_ICON_DESC"])
    row.class = Kit.AttachList(Kit.Button(row, "", 88), ClassOptions,
        function() return D(i).entry.class or "" end,
        function(class) MK.MobDB:SetClass(D(i).entry, class ~= "" and class or nil) end, 120)
    row.class:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    Kit.Tooltip(row.class, L["TYPE_CC"], L["MOBS_CLASS_DESC"])
    row.delete = Kit.Button(row, "X", 26, function()
        if rowData[i] then MK.MobDB:Delete(page.zone, D(i).kind, D(i).key) end
    end)
    row.delete:SetPoint("LEFT", row.class, "RIGHT", 6, 0)
    return row
end

local function StepZone(delta)
    local zones = MK.MobDB:Zones(MK.Plates.zone)
    if #zones == 0 then return end
    local idx = 1
    for i, z in ipairs(zones) do if z == mobsPage.zone then idx = i end end
    idx = (idx - 1 + delta) % #zones + 1
    mobsPage.zone, mobsPage.page = zones[idx], 1
    mobsPage:refresh()
end

mobsPage = NS:AddPage(area.key, {
    key = "mobs",
    title = NS.L["PAGE_MOBS"],
    build = function(page, parent)
        page.zone, page.page = MK.Plates.zone, 1
        page.prevZone = Kit.Button(parent, L["BTN_PREV"], 28, function() StepZone(-1) end)
        page.prevZone:SetPoint("TOPLEFT", 0, 0)
        -- Any zone in one click (user 2026-11-14); the arrows still step to the neighbours.
        page.zoneDrop = Kit.Dropdown(parent, 320, function()
            local opts = {}
            for _, zone in ipairs(MK.MobDB:Zones(MK.Plates.zone)) do
                local label = string.format(L["MOBS_ZONE"], zone, #MK.MobDB:Entries(zone))
                if zone == MK.Plates.zone then label = label .. " " .. L["MOBS_ZONE_HERE"] end
                opts[#opts + 1] = { key = zone, label = label }
            end
            return opts
        end, function() return page.zone end, function(zone)
            page.zone, page.page = zone, 1
            page:refresh()
        end)
        page.zoneDrop:SetPoint("LEFT", page.prevZone, "RIGHT", 6, 0)
        Kit.Tooltip(page.zoneDrop, L["MOBS_ZONE_PICK"], L["MOBS_ZONE_PICK_DESC"])
        page.nextZone = Kit.Button(parent, L["BTN_NEXT"], 28, function() StepZone(1) end)
        page.nextZone:SetPoint("LEFT", page.zoneDrop, "RIGHT", 6, 0)

        local card = Card(parent, nil, -34, MOB_ROWS * MOB_ROW_H + 50)
        page.empty = Kit.Paragraph(card, L["MOBS_EMPTY"], 600, 12, C.muted)
        page.empty:SetPoint("TOPLEFT", 16, -16)
        page.rows = {}
        for i = 1, MOB_ROWS do page.rows[i] = MobRow(card, i) end
        page.rows[1]:SetPoint("TOPLEFT", 10, -10)
        for i = 2, MOB_ROWS do page.rows[i]:SetPoint("TOPLEFT", 10, -10 - (i - 1) * MOB_ROW_H) end

        local by = -34 - (MOB_ROWS * MOB_ROW_H + 50) - 10
        local learn = Kit.Button(parent, L["BTN_LEARN_TARGET"], 130, function()
            local _, label = MK.MobDB:Learn("target")
            if label then MK:Print(L["LEARN_SAVED"], label, L["TYPE_TANK"]) else MK:Print(L["LEARN_NO_UNIT"]) end
            page.zone = MK.Plates.zone
            page:refresh()
        end)
        learn:SetPoint("TOPLEFT", 0, by)
        Kit.Tooltip(learn, L["BTN_LEARN_TARGET"], L["BTN_LEARN_TARGET_DESC"])
        page.nextPage = Kit.Button(parent, L["BTN_NEXT"], 28, function() page.page = page.page + 1; page:refresh() end)
        page.nextPage:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, by)
        page.pageText = Kit.Text(parent, 12)
        page.pageText:SetPoint("RIGHT", page.nextPage, "LEFT", -8, 0)
        page.prevPage = Kit.Button(parent, L["BTN_PREV"], 28, function() page.page = page.page - 1; page:refresh() end)
        page.prevPage:SetPoint("RIGHT", page.pageText, "LEFT", -8, 0)
    end,
    refresh = function(page)
        local zones = MK.MobDB:Zones(MK.Plates.zone)
        local found = false
        for _, z in ipairs(zones) do if z == page.zone then found = true end end
        if not found then page.zone = MK.Plates.zone ~= "" and MK.Plates.zone or zones[1] end
        local entries = page.zone and MK.MobDB:Entries(page.zone) or {}
        page.zoneDrop:Refresh()
        page.zoneDrop:SetActive(#zones > 0)
        page.prevZone:SetActive(#zones > 1)
        page.nextZone:SetActive(#zones > 1)
        local pages = math.max(1, math.ceil(#entries / MOB_ROWS))
        page.page = math.max(1, math.min(page.page or 1, pages))
        page.pageText:SetText(string.format(L["MOBS_PAGE"], page.page, pages))
        page.prevPage:SetActive(page.page > 1)
        page.nextPage:SetActive(page.page < pages)
        page.empty:SetShown(#entries == 0)
        for i, row in ipairs(page.rows) do
            local data = entries[(page.page - 1) * MOB_ROWS + i]
            rowData[i] = data
            row:SetShown(data ~= nil)
            if data then
                local e = data.entry
                local isSig = data.kind == "sig"
                row.kind:SetText(isSig and (MK.MobDB.LevelText(e) or L["MOBS_KIND_SIG"]) or L["MOBS_KIND_NAME"])
                row.label:SetShown(not isSig)
                row.note:SetShown(isSig)
                if isSig then
                    if not row.note:HasFocus() then row.note:SetText(data.label) end
                else
                    row.label:SetText(data.label)
                end
                row.type:SetLabel(L["TYPE_" .. (e.type or "TANK")])
                local killOrCC = e.type ~= "IGNORE"
                row.prio:SetText(killOrCC and tostring(e.prio or 5) or "-")
                row.minus:SetActive(killOrCC)
                row.plus:SetActive(killOrCC)
                row.icon:SetActive(killOrCC)
                if e.icon then
                    row.icon:SetLabel("")
                    row.iconTex:SetTexCoord(Utils.IconTexCoord(e.icon))
                    row.iconTex:Show()
                else
                    row.icon:SetLabel(L["MOBS_AUTO"])
                    row.iconTex:Hide()
                end
                row.class:SetShown(e.type == "CC")
                row.class:SetLabel(ClassLabel(e.class))
            end
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Briefing: per dungeon, every mob's casts with Bulwark's default priority; your choice overrides it, plus a note
-- for the group (Briefing.lua, build step 4). Paged like Mobs; dungeon picked from the ability data.
-- Columns are anchored to the card's edges (the window scales: fixed widths ran past the card [in-game 2026-11-15]).
---------------------------------------------------------------------------------------------------------------

local BRIEF_ROWS = 12
local BRIEF_ROW_H = 26
local BRIEF_HEAD_H = 22
-- x of each column inside a row (rows start 10 px into the card); the note column runs to the row's right edge.
local COL_SPELL, COL_DEFAULT, COL_YOURS, COL_NOTE = 18, 194, 262, 376
local COL_SPELL_W, COL_DEFAULT_W, COL_YOURS_W = 170, 64, 104
local briefData = {}   -- [row index] = AbilityRows item (plain table, see rowData)
local briefPage
local PRIO_TEXT_COLOR = { must = "ffff5555", should = "ffffd100", info = "ff66ccff", ignore = "ff9d9d9d" }
local SEEN_MARK = " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"   -- seen in play (tooltip says how)

local function PrioText(prio)
    return "|c" .. PRIO_TEXT_COLOR[prio] .. L["BRIEF_PRIO_" .. prio] .. "|r"
end

local function DefaultLabel()
    return "|cff9d9d9d" .. L["BRIEF_PAGE_DEFAULT"] .. "|r"
end

local function BriefPrioOptions()
    local opts = { { key = "", label = DefaultLabel() } }
    for _, prio in ipairs({ "must", "should", "info", "ignore" }) do opts[#opts + 1] = { key = prio, label = PrioText(prio) } end
    return opts
end

-- Dungeons with ability data or with casts seen in play (Forever-only dungeons fill this way).
local function BriefInstances()
    local list, seen = {}, {}
    for id, name in pairs(MK.MobAbilityInstances or {}) do list[#list + 1] = { id = id, name = name }; seen[id] = true end
    for id, name in pairs(MK.Briefing.LearnedInstances()) do
        if not seen[id] then list[#list + 1] = { id = id, name = name } end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function SaveNote(i, box)
    local r = briefData[i]
    if not (r and r.spell) then return end
    local o = r.override or {}
    MK.Briefing.SetOverride(r.mob, r.spell.id, o.prio, box:GetText())
end

-- Grey "note for the group" in an empty, unfocused box.
local function UpdatePlaceholder(box)
    box.placeholder:SetShown(box:GetText() == "" and not box:HasFocus())
end

local function BriefRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BRIEF_ROW_H)
    row.mob = Kit.Text(row, 12, C.goldText)
    row.mob:SetPoint("LEFT", 2, 0)
    row.spellBtn = CreateFrame("Button", nil, row)
    row.spellBtn:SetPoint("LEFT", COL_SPELL, 0)
    row.spellBtn:SetSize(COL_SPELL_W, BRIEF_ROW_H)
    row.spell = Kit.Text(row.spellBtn, 12)
    row.spell:SetPoint("LEFT", 0, 0)
    row.spell:SetWidth(COL_SPELL_W)
    row.spell:SetWordWrap(false)
    row.spellBtn:SetScript("OnEnter", function(self)
        local r = briefData[i]
        if not (r and r.spell) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(MK.Abilities.Describe(r.spell), 1, 1, 1, 1, true)
        GameTooltip:AddLine(string.format(L["BRIEF_PAGE_DEFAULT_TIP"], PrioText(r.auto),
            L["BRIEF_PAGE_SRC_" .. r.autoSource]), nil, nil, nil, true)
        if r.seen then
            GameTooltip:AddLine(string.format(r.seen.how == "kick" and L["BRIEF_SEEN_KICK"] or L["BRIEF_SEEN_HIT"],
                r.seen.n or 1), 0.4, 1, 0.4, true)
        end
        GameTooltip:Show()
    end)
    row.spellBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.auto = Kit.Text(row, 12)
    row.auto:SetPoint("LEFT", COL_DEFAULT, 0)
    row.auto:SetWidth(COL_DEFAULT_W)
    row.auto:SetJustifyH("LEFT")
    row.prio = Kit.AttachList(Kit.Button(row, "", COL_YOURS_W), BriefPrioOptions,
        function() local r = briefData[i]; return r and r.override and r.override.prio or "" end,
        function(prio)
            local r = briefData[i]
            if not (r and r.spell) then return end
            MK.Briefing.SetOverride(r.mob, r.spell.id, prio ~= "" and prio or nil, r.override and r.override.note)
        end, 110,
        function()
            local r = briefData[i]
            if r and r.spell then MK.Briefing.SetOverride(r.mob, r.spell.id, nil, r.override and r.override.note) end
        end)
    row.prio:SetPoint("LEFT", COL_YOURS, 0)
    Kit.Tooltip(row.prio, L["BRIEF_COL_YOURS"], L["BRIEF_PAGE_PRIO_DESC"])
    row.note = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.note:SetHeight(20)
    row.note:SetPoint("LEFT", COL_NOTE + 6, 0)    -- InputBoxTemplate's left cap sits 5 px outside the box
    row.note:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.note:SetAutoFocus(false)
    row.note:SetMaxLetters(80)
    row.note.placeholder = Kit.Text(row.note, 11, C.muted)
    row.note.placeholder:SetPoint("LEFT", 2, 0)
    row.note.placeholder:SetText(L["BRIEF_PAGE_NOTE_HINT"])
    row.note:SetScript("OnTextChanged", UpdatePlaceholder)
    row.note:SetScript("OnEditFocusGained", UpdatePlaceholder)
    row.note:SetScript("OnEnterPressed", function(self)
        SaveNote(i, self)
        self:ClearFocus()
    end)
    row.note:SetScript("OnEscapePressed", function(self)
        self.cancel = true
        self:ClearFocus()
        briefPage:refresh()
    end)
    row.note:SetScript("OnEditFocusLost", function(self)
        UpdatePlaceholder(self)
        if self.cancel then self.cancel = false return end
        SaveNote(i, self)
    end)
    row.note:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BRIEF_COL_NOTE"], 1, 1, 1)
        GameTooltip:AddLine(L["BRIEF_PAGE_NOTE_DESC"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row.note:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function StepBriefZone(delta)
    local list = BriefInstances()
    local idx = 1
    for i, z in ipairs(list) do if z.id == briefPage.instance then idx = i end end
    idx = (idx - 1 + delta) % #list + 1
    briefPage.instance, briefPage.page = list[idx].id, 1
    briefPage:refresh()
end

briefPage = NS:AddPage(area.key, {
    key = "briefing",
    title = NS.L["PAGE_BRIEFING"],
    build = function(page, parent)
        page.page = 1
        page.prevZone = Kit.Button(parent, L["BTN_PREV"], 28, function() StepBriefZone(-1) end)
        page.prevZone:SetPoint("TOPLEFT", 0, 0)
        page.zoneDrop = Kit.Dropdown(parent, 300, function()
            local opts = {}
            for _, z in ipairs(BriefInstances()) do
                local label = z.name
                if z.id == MK.Plates.instanceID then label = label .. " " .. L["MOBS_ZONE_HERE"] end
                opts[#opts + 1] = { key = z.id, label = label }
            end
            return opts
        end, function() return page.instance end, function(id)
            page.instance, page.page = id, 1
            page:refresh()
        end)
        page.zoneDrop:SetPoint("LEFT", page.prevZone, "RIGHT", 6, 0)
        page.nextZone = Kit.Button(parent, L["BTN_NEXT"], 28, function() StepBriefZone(1) end)
        page.nextZone:SetPoint("LEFT", page.zoneDrop, "RIGHT", 6, 0)
        -- The tile switch lives here (was Marking > Options, which is about pack planning).
        page.tile = Kit.Checkbox(parent, L["OPT_BRIEF_TILE"], L["OPT_BRIEF_TILE_DESC"], function(checked)
            MK:Set("briefTile", checked)
            MK.BriefingTile:Refresh()
        end)
        page.tile:SetPoint("LEFT", page.nextZone, "RIGHT", 18, 0)

        local cardH = BRIEF_HEAD_H + BRIEF_ROWS * BRIEF_ROW_H + 18
        local card = Card(parent, nil, -34, cardH)
        -- Column headings
        local heads = { { COL_SPELL, "BRIEF_COL_SPELL" }, { COL_DEFAULT, "BRIEF_COL_DEFAULT" },
                        { COL_YOURS, "BRIEF_COL_YOURS" }, { COL_NOTE, "BRIEF_COL_NOTE" } }
        for _, h in ipairs(heads) do
            local fs = Kit.Text(card, 11, C.muted)
            fs:SetPoint("TOPLEFT", 10 + h[1], -10)
            fs:SetText(L[h[2]])
        end
        Kit.HLine(card, -10 - BRIEF_HEAD_H + 4, C.line, 10)
        page.rows = {}
        for i = 1, BRIEF_ROWS do
            local row = BriefRow(card, i)
            row:SetPoint("TOPLEFT", 10, -10 - BRIEF_HEAD_H - (i - 1) * BRIEF_ROW_H)
            row:SetPoint("RIGHT", card, "RIGHT", -10, 0)
            page.rows[i] = row
        end

        local by = -34 - cardH - 8
        page.nextPage = Kit.Button(parent, L["BTN_NEXT"], 28, function() page.page = page.page + 1; page:refresh() end)
        page.nextPage:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, by)
        page.pageText = Kit.Text(parent, 12)
        page.pageText:SetPoint("RIGHT", page.nextPage, "LEFT", -8, 0)
        page.prevPage = Kit.Button(parent, L["BTN_PREV"], 28, function() page.page = page.page - 1; page:refresh() end)
        page.prevPage:SetPoint("RIGHT", page.pageText, "LEFT", -8, 0)
        -- What the priorities do, in one place (instead of a tooltip per row)
        page.help = Kit.Paragraph(parent, L["BRIEF_PAGE_HELP"], 400, 11, C.muted)
        page.help:SetPoint("TOPLEFT", 0, by)
        page.help:SetPoint("RIGHT", page.prevPage, "LEFT", -16, 0)
    end,
    refresh = function(page)
        page.tile:SetChecked(MK:Get("briefTile") and true or false)
        local here = MK.Plates.instanceID
        local function Known(id)
            return id and ((MK.MobAbilities and MK.MobAbilities[id]) or next(MK.Briefing.LearnedMobs(id)) ~= nil)
        end
        if not Known(page.instance) then
            page.instance = Known(here) and here or 389   -- Ragefire Chasm
        end
        page.zoneDrop:Refresh()
        local rows = MK.Briefing.AbilityRows(page.instance)
        local pages = math.max(1, math.ceil(#rows / BRIEF_ROWS))
        page.page = math.max(1, math.min(page.page or 1, pages))
        page.pageText:SetText(string.format(L["MOBS_PAGE"], page.page, pages))
        page.prevPage:SetActive(page.page > 1)
        page.nextPage:SetActive(page.page < pages)
        for i, row in ipairs(page.rows) do
            local r = rows[(page.page - 1) * BRIEF_ROWS + i]
            briefData[i] = r
            row:SetShown(r ~= nil)
            if r then
                local isMob = r.spell == nil
                row.mob:SetShown(isMob)
                row.spellBtn:SetShown(not isMob)
                row.auto:SetShown(not isMob)
                row.prio:SetShown(not isMob)
                row.note:SetShown(not isMob)
                if isMob then
                    row.mob:SetText(r.mob .. (r.boss and ("  |cff9d9d9d" .. L["BRIEF_BOSS"] .. "|r") or ""))
                else
                    row.spell:SetText(MK.Briefing.SpellName(r.spell.id) .. (r.seen and SEEN_MARK or ""))
                    row.auto:SetText(PrioText(r.auto))
                    local o = r.override
                    row.prio:SetLabel(o and o.prio and PrioText(o.prio) or DefaultLabel())
                    if not row.note:HasFocus() then row.note:SetText(o and o.note or "") end
                    UpdatePlaceholder(row.note)
                end
            end
        end
    end,
})
MK:On("BRIEFING_CHANGED", function() RefreshIfShown(briefPage) end)

---------------------------------------------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------------------------------------------

local OPTIONS = {
    { key = "overlay", text = "OPT_OVERLAY" },
    { key = "shiftSelect", text = "OPT_SHIFT" },
    { key = "nearOnly", text = "OPT_NEAR" },
    { key = "record", text = "OPT_RECORD" },
    { key = "learnNames", text = "OPT_LEARN" },
}

-- Rows stack by each description's real height, at the card's real width (the window scales: a fixed width ran past
-- the card's right edge [in-game 2026-11-15]). Runs again whenever the card's width changes.
local function LayoutOptions(page)
    local card = page.card
    local w = tonumber(card:GetWidth()) or 0
    if w <= 0 then w = 640 end
    if page.laidOutAt == w then return end
    page.laidOutAt = w
    local rowY = -38
    for _, opt in ipairs(OPTIONS) do
        local cb, note = page.boxes[opt.key], page.notes[opt.key]
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 12, rowY)
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", 44, rowY - 24)
        note:SetWidth(w - 44 - 16)
        local h = tonumber(note:GetStringHeight()) or 0
        if h <= 0 then h = 28 end
        rowY = rowY - 24 - h - 12
    end
    card:SetHeight(-rowY)
end

NS:AddPage(area.key, {
    key = "options",
    title = NS.L["PAGE_OPTIONS"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, NS.L["PAGE_OPTIONS"], NS.L["MARK_OPTIONS_DESC"])
        local card = Card(parent, NS.L["MARK_CARD_PLANNING"], y, 40)
        page.card, page.boxes, page.notes = card, {}, {}
        for _, opt in ipairs(OPTIONS) do
            page.boxes[opt.key] = Kit.Checkbox(card, L[opt.text], nil, function(checked)
                MK:Set(opt.key, checked)
                if opt.key == "overlay" then
                    MK.Overlay:Show(MK.Planner.plan)
                elseif opt.key == "nearOnly" then
                    if checked then
                        for token, rec in pairs(MK.Plates.records) do
                            rec.far, rec.hidden = MK.Plates.IsFar(token), MK.Plates.IsHidden(token)
                        end
                    end
                    MK.Plates.Changed()
                elseif opt.key == "record" and checked then
                    MK.MobDB:RecordVisible()
                end
            end)
            page.notes[opt.key] = Note(card, L[opt.text .. "_DESC"], 44, 0, 560)
        end
        card:HookScript("OnSizeChanged", function() LayoutOptions(page) end)
        LayoutOptions(page)
    end,
    refresh = function(page)
        for key, cb in pairs(page.boxes) do cb:SetChecked(MK:Get(key) and true or false) end
        LayoutOptions(page)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Keys (bindings, old macros)
---------------------------------------------------------------------------------------------------------------

local KEY_ROWS = {
    { button = "PackButton", label = "KEY_PACK" },
    { button = "SkullButton", label = "KEY_SKULL" },
    { button = "CycleButton", label = "KEY_CYCLE" },
    { button = "ClearButton", label = "KEY_CLEAR" },
    { button = "BriefButton", label = "KEY_BRIEF" },
}

NS:AddPage(area.key, {
    key = "keys",
    title = NS.L["PAGE_KEYS"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, NS.L["PAGE_KEYS"], NS.L["MARK_KEYS_DESC"])
        local card = Card(parent, NS.L["MARK_CARD_KEYS"], y, 40 + #KEY_ROWS * 26 + 30)
        page.keys = {}
        for i, def in ipairs(KEY_ROWS) do
            local name = Kit.Text(card, 12)
            name:SetPoint("TOPLEFT", 16, -42 - (i - 1) * 26)
            name:SetText(NS.L[def.label])
            local key = Kit.Text(card, 12, C.goldText)
            key:SetPoint("TOPLEFT", 330, -42 - (i - 1) * 26)
            page.keys[def.button] = key
        end
        Note(card, NS.L["MARK_KEYS_WHERE"], 16, -42 - #KEY_ROWS * 26 - 4, 600)

        local macros = Card(parent, NS.L["MARK_CARD_MACROS"], y - (40 + #KEY_ROWS * 26 + 30) - 10, 110)
        page.macros = Kit.Paragraph(macros, "", 600, 12)
        page.macros:SetPoint("TOPLEFT", 16, -42)
        local move = Kit.Button(macros, NS.L["MARK_BTN_MOVE_KEYS"], 200, function()
            local moved = MK.Keys.MoveOldBindings()
            if moved == nil then
                MK:Print(L["COMBAT_LOCKED"])
            elseif #moved > 0 then
                MK:Print(L["KEYS_MOVED"], table.concat(moved, ", "))
            else
                MK:Print(NS.L["MARK_NO_OLD_KEYS"])
            end
            page:refresh()
        end)
        move:SetPoint("BOTTOMLEFT", 14, 12)
        Kit.Tooltip(move, NS.L["MARK_BTN_MOVE_KEYS"], NS.L["MARK_BTN_MOVE_KEYS_TIP"])
    end,
    refresh = function(page)
        local keys = MK.Keys.Current()
        for button, fs in pairs(page.keys) do
            fs:SetText(keys[button] or L["KEY_UNBOUND"])
        end
        local old = MK.Keys.OldMacros()
        page.macros:SetText(#old > 0 and string.format(NS.L["MARK_OLD_MACROS"], table.concat(old, ", "))
            or NS.L["MARK_NO_OLD_MACROS"])
    end,
})

MK:On("SETUP_CHANGED", function() RefreshIfShown(teamPage) end)
MK:On("MOBDB_CHANGED", function() RefreshIfShown(mobsPage) end)

---------------------------------------------------------------------------------------------------------------
-- /bwk mark ...: from TankMarkForever UI/Commands.lua
---------------------------------------------------------------------------------------------------------------

local function OnOff(v) return v and NS.L["STATUS_ON"] or NS.L["STATUS_OFF"] end

-- The mob to learn: mouseover first (out of combat, deliberate), then the target.
local LEARN_UNITS = { "mouseover", "target" }

local function Learn(arg1, arg2)
    local entry
    local icon = tonumber(arg2)
    local class = not icon and arg2 and MK.Team.CC_SPELL[string.upper(arg2)] and string.upper(arg2) or nil
    if arg1 == "ignore" then
        entry = { type = "IGNORE" }
    elseif arg1 == "cc" then
        entry = { type = "CC", prio = 9, icon = icon, class = class }
    elseif tonumber(arg1) and tonumber(arg1) >= 1 and tonumber(arg1) <= 9 then
        entry = { type = "TANK", prio = tonumber(arg1), icon = icon }
    else
        MK:Print(L["LEARN_USAGE"])
        return
    end
    if entry.icon and (entry.icon < 1 or entry.icon > 8) then entry.icon = nil end
    for _, unit in ipairs(LEARN_UNITS) do
        local saved, label = MK.MobDB:Learn(unit, entry)
        if saved then
            local what = saved.type == "IGNORE" and "ignore"
                or string.format("%s prio %d%s%s", saved.type, saved.prio,
                    saved.icon and (" " .. Utils.IconText(saved.icon)) or "", saved.class and (" " .. saved.class) or "")
            MK:Print(L["LEARN_SAVED"], label, what)
            return
        end
    end
    MK:Print(L["LEARN_NO_UNIT"])
end

local function Forget()
    for _, unit in ipairs(LEARN_UNITS) do
        if UnitExists(unit) then
            local label = MK.MobDB:ForgetUnit(unit)
            if label then MK:Print(L["LEARN_FORGOT"], label) else MK:Print(L["LEARN_NOT_FOUND"], unit) end
            return
        end
    end
    MK:Print(L["LEARN_NO_UNIT"])
end

local function Status()
    MK:Print("%s: %s", NS.L["AREA_MARKING"], OnOff(MK.isEnabled))
    print(string.format(L["STATUS_OPTIONS"], OnOff(MK:Get("overlay")), OnOff(MK:Get("shiftSelect"))))
    local keys = MK.Keys.Current()
    print(string.format(L["STATUS_KEYS"], keys.PackButton or L["KEY_UNBOUND"], keys.SkullButton or L["KEY_UNBOUND"],
        keys.CycleButton or L["KEY_UNBOUND"], keys.ClearButton or L["KEY_UNBOUND"]))
    local zoneMobs = MK.db.mobs[MK.Plates.zone] or { names = {}, sigs = {} }
    local nNames, nSigs = 0, 0
    for _ in pairs(zoneMobs.names) do nNames = nNames + 1 end
    for _ in pairs(zoneMobs.sigs) do nSigs = nSigs + 1 end
    print(string.format(L["STATUS_ZONE"], MK.Plates.zone, MK.Plates.inInstance and "instance" or "open world",
        nNames, nSigs))
    local id = MK.Plates.instanceID
    print(string.format(L["STATUS_INSTANCE"], tostring(id),
        (id and MK.InstanceMobs[id]) and L["STATUS_DATA_YES"] or L["STATUS_DATA_NO"]))
end

area.commandHelp = {
    "|cffffd160/bwk mark|r announce||plan||status  " .. NS.L["HELP_MARK_MAIN"],
    "|cffffd160/bwk mark learn|r <1-9||ignore||cc> [icon||class], |cffffd160forget|r  " .. NS.L["HELP_MARK_LEARN"],
    "|cffffd160/bwk mark|r select clear, overlay  " .. NS.L["HELP_MARK_MISC"],
    "|cffffd160/bwk mark abilities|r [name]  " .. NS.L["HELP_MARK_ABILITIES"],
    "|cffffd160/bwk mark brief|r [preview||status||test]  " .. NS.L["HELP_MARK_BRIEF"],
}

function area.command(args)
    local cmd, arg1, arg2 = strsplit(" ", string.lower(strtrim(args or "")))
    local running = NS:IsAreaRunning("marking")
    if cmd == "announce" then
        MK.Team:Announce()
    elseif cmd == "status" then
        Status()
    elseif cmd == "abilities" then
        -- The name keeps its case: take it from the raw arguments.
        MK.Abilities.Report((args or ""):match("^%s*%S+%s+(.-)%s*$"))
    elseif not running then
        MK:Print(NS.L["MARK_NOT_RUNNING"])
    elseif cmd == "plan" then
        MK.Planner:Report()
    elseif cmd == "brief" then
        if arg1 == "preview" then
            MK.Briefing.Preview()
        elseif arg1 == "test" then
            MK.BriefingTile.ToggleSoloTest()
        elseif arg1 == "status" then
            MK.BriefingTile.Status()
        else
            MK.BriefingTile.Post()
        end
    elseif cmd == "select" and arg1 == "clear" then
        MK.Plates:ClearSelection()
    elseif cmd == "learn" then
        Learn(arg1, arg2)
    elseif cmd == "forget" then
        Forget()
    elseif cmd == "overlay" then
        MK:Set("overlay", not MK:Get("overlay"))
        MK.Overlay:Show(MK.Planner.plan)
        MK:Print("%s: %s", L["OPT_OVERLAY"], OnOff(MK:Get("overlay")))
    else
        for _, line in ipairs(area.commandHelp) do print("  " .. line) end
    end
end
