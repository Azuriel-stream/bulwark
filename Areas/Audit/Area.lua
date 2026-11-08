local ADDON_NAME, NS = ...
local L, Kit, D, Utils = NS.L, NS.Kit, NS.AuditData, NS.Utils
local C = Kit.C

-- Audit: pre-pull tiles for missing buffs, consumables, dispellable debuffs and unwanted buffs; buff requests and
-- thank-you whispers (from TankAuditForever). Warrior and Paladin tanks.
local area = NS:RegisterArea({
    key = "audit",
    order = 2,
    title = L["AREA_AUDIT"],
    desc = L["AREA_AUDIT_DESC"],
    icon = "tab_audit",
    legacy = "TankAuditForever",
})

NS.DefaultConfig.audit = {
    locked = true,
    scale = 1.0,
    point = { "CENTER", "CENTER", 0, -100 },   -- point, relativePoint (on UIParent), x, y
    checkSelf = true,
    checkGroup = true,
    checkConsumables = true,
    consumableLevel = 1,        -- 1 = food only, 2 = + elixir, 3 = + flask
    checkHealthstone = true,
    checkDebuffs = true,
    checkUnwanted = true,
    gratitude = true,           -- whisper the caster when a requested buff arrives
    watchSound = true,          -- in-combat sound when Battle Shout / Righteous Fury is about to fade
    watchWarnSeconds = 15,
    watchDurations = {},        -- [spellID] = real duration learned out of combat
    -- With N paladins in the group, the first N entries are expected (per tank class).
    blessingPriority = {
        WARRIOR = { "KINGS", "MIGHT", "LIGHT", "WISDOM" },
        PALADIN = { "KINGS", "WISDOM", "MIGHT", "LIGHT" },
    },
}

local function cfg() return NS.db.audit end
local function Supported() return D.SELF[NS.playerClass] ~= nil end
local function Rescan() NS.AuditScanner:Queue() end

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

-- Page header plus, for classes Audit doesn't cover, a note under it. Returns the y where content starts.
local function Header(parent, title, desc)
    local y = Kit.PageHeader(parent, title, desc)
    if Supported() then return y end
    local card = Card(parent, nil, y, 44)
    local text = Kit.Text(card, 12, C.warn)
    text:SetPoint("LEFT", 16, 0)
    text:SetText(string.format(L["AUDIT_CLASS_UNSUPPORTED"],
        (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[NS.playerClass]) or NS.playerClass or "?"))
    return y - 54
end

-- Tiles are previewed (all shown, debuff squares visible) while the window shows this tab.
NS:On("WINDOW_CHANGED", function(shown, areaKey)
    NS.AuditBar:SetWindowPreview(shown and areaKey == "audit")
end)

---------------------------------------------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------------------------------------------

local CHECKS = {
    { key = "checkSelf", text = "AUDIT_OPT_SELF", col = 0 },
    { key = "checkGroup", text = "AUDIT_OPT_GROUP", col = 1 },
    { key = "checkConsumables", text = "AUDIT_OPT_CONSUMABLES", col = 0 },
    { key = "checkHealthstone", text = "AUDIT_OPT_HEALTHSTONE", col = 1 },
    { key = "checkDebuffs", text = "AUDIT_OPT_DEBUFFS", col = 0 },
    { key = "checkUnwanted", text = "AUDIT_OPT_UNWANTED", col = 1 },
}

NS:AddPage(area.key, {
    key = "checks",
    title = L["PAGE_CHECKS"],
    build = function(page, parent)
        local y = Header(parent, L["PAGE_CHECKS"], L["AUDIT_CHECKS_DESC"])
        local card = Card(parent, L["AUDIT_CARD_CHECKS"], y, 140)
        page.checks = {}
        for i, def in ipairs(CHECKS) do
            local cb = Kit.Checkbox(card, L[def.text], L[def.text .. "_DESC"], function(checked)
                cfg()[def.key] = checked
                Rescan()
            end)
            cb:SetPoint("TOPLEFT", 12 + def.col * 300, -38 - math.floor((i - 1) / 2) * 32)
            page.checks[def.key] = cb
        end

        -- Consumables: "+ Elixir" / "+ Flask" on top of food, at most one (radio-like checkboxes; no dropdowns,
        -- kb/gotchas.md#menu-crash).
        local cons = Card(parent, L["AUDIT_CARD_CONSUMABLES"], y - 150, 98)
        page.consumables = {}
        for i, opt in ipairs({ { level = 2, label = "AUDIT_CONS_ELIXIR" }, { level = 3, label = "AUDIT_CONS_FLASK" } }) do
            local cb = Kit.Checkbox(cons, L[opt.label], L["AUDIT_CONS_DESC"], function(checked)
                cfg().consumableLevel = checked and opt.level or 1
                page:refresh()
                Rescan()
            end)
            cb:SetPoint("TOPLEFT", 12 + (i - 1) * 300, -38)
            page.consumables[opt.level] = cb
        end
        Note(cons, L["AUDIT_CONS_DESC"], 16, -68, 600)

        local thanks = Card(parent, L["AUDIT_CARD_THANKS"], y - 258, 70)
        page.gratitude = Kit.Checkbox(thanks, L["AUDIT_OPT_GRATITUDE"], L["AUDIT_OPT_GRATITUDE_DESC"], function(checked)
            cfg().gratitude = checked
        end)
        page.gratitude:SetPoint("TOPLEFT", 12, -38)
    end,
    refresh = function(page)
        for key, cb in pairs(page.checks) do cb:SetChecked(cfg()[key]) end
        for level, cb in pairs(page.consumables) do cb:SetChecked(cfg().consumableLevel == level) end
        page.gratitude:SetChecked(cfg().gratitude)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Blessings (priority for the player's class)
---------------------------------------------------------------------------------------------------------------

local function BlessingName(key)
    local def = D.BLESSINGS[key]
    return (def and Utils.SpellName(def.ids[1])) or key
end

NS:AddPage(area.key, {
    key = "blessings",
    title = L["PAGE_BLESSINGS"],
    build = function(page, parent)
        local y = Header(parent, L["PAGE_BLESSINGS"], L["AUDIT_BLESSINGS_DESC"])
        local card = Card(parent, L["AUDIT_CARD_PRIORITY"], y, 48 + 4 * 34)
        page.rows = {}
        for i = 1, 4 do
            local ry = -40 - (i - 1) * 34
            local row = {}
            row.icon = card:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("TOPLEFT", 16, ry)
            row.label = Kit.Text(card, 13)
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
            row.up = Kit.Button(card, L["BTN_UP"], 60, function()
                NS.AuditScanner.MoveBlessing(i, -1)
                page:refresh()
                Rescan()
            end)
            row.up:SetPoint("TOPLEFT", 300, ry)
            row.down = Kit.Button(card, L["BTN_DOWN"], 60, function()
                NS.AuditScanner.MoveBlessing(i, 1)
                page:refresh()
                Rescan()
            end)
            row.down:SetPoint("LEFT", row.up, "RIGHT", 8, 0)
            page.rows[i] = row
        end
    end,
    refresh = function(page)
        local priority = NS.AuditScanner.BlessingPriority()
        for i, row in ipairs(page.rows) do
            local key = priority[i]
            row.label:SetText(key and (i .. ".  " .. BlessingName(key)) or "")
            row.icon:SetTexture(key and D.BLESSINGS[key] and D.BLESSINGS[key].icon or nil)
            row.up:SetActive(i > 1)
            row.down:SetActive(i < #priority)
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Tiles (position, size, lock)
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "tiles",
    title = L["PAGE_TILES"],
    build = function(page, parent)
        local y = Header(parent, L["PAGE_TILES"], L["AUDIT_TILES_DESC"])
        local card = Card(parent, L["AUDIT_CARD_TILES"], y, 136)
        page.lock = Kit.Checkbox(card, L["AUDIT_OPT_LOCK"], L["AUDIT_OPT_LOCK_DESC"], function(checked)
            NS.AuditBar:SetLocked(checked, true)
        end)
        page.lock:SetPoint("TOPLEFT", 12, -38)
        local reset = Kit.Button(card, L["AUDIT_BTN_RESET"], 150, function() NS.AuditBar:ResetPosition() end)
        reset:SetPoint("TOPLEFT", 312, -40)
        page.scale = Kit.Slider(card, L["AUDIT_OPT_SCALE"], 50, 200, 10,
            function(v) return string.format("%d%%", v) end,
            function(v) NS.AuditBar:SetScale(v / 100) end)
        page.scale:SetPoint("TOPLEFT", 12, -96)
        Note(parent, L["AUDIT_PREVIEW_NOTE"], 0, y - 148, 640)
    end,
    refresh = function(page)
        page.lock:SetChecked(cfg().locked)
        page.scale:SetValue(math.floor(cfg().scale * 100 + 0.5))
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Sound (in-combat self-buff warning)
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "sound",
    title = L["PAGE_SOUND"],
    build = function(page, parent)
        local y = Header(parent, L["PAGE_SOUND"], L["AUDIT_SOUND_DESC"])
        local card = Card(parent, L["AUDIT_CARD_SOUND"], y, 98)
        page.sound = Kit.Checkbox(card, L["AUDIT_OPT_SOUND"], nil, function(checked)
            cfg().watchSound = checked
        end)
        page.sound:SetPoint("TOPLEFT", 12, -38)
        Note(card, L["AUDIT_OPT_SOUND_DESC"], 44, -66, 580)
    end,
    refresh = function(page)
        page.sound:SetChecked(cfg().watchSound)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Tools (scan, dump, current plan)
---------------------------------------------------------------------------------------------------------------

local function PlanSummary()
    local plan = NS.AuditScanner.plan or { tiles = {} }
    local names = {}
    for _, item in ipairs(plan.tiles or {}) do names[#names + 1] = item.label or item.key end
    local types = {}
    for dtype, action in pairs(plan.dispelActions or {}) do types[#types + 1] = L[dtype] .. " (" .. L["AUDIT_ACTION_" .. action.type] .. ")" end
    table.sort(types)
    return #names > 0 and table.concat(names, ", ") or "-", #types > 0 and table.concat(types, ", ") or "-",
        plan.salvation and L["STATUS_ON"] or L["STATUS_OFF"]
end

NS:AddPage(area.key, {
    key = "tools",
    title = L["PAGE_TOOLS"],
    build = function(page, parent)
        local y = Header(parent, L["PAGE_TOOLS"], L["AUDIT_TOOLS_DESC"])
        local card = Card(parent, L["AUDIT_CARD_TOOLS"], y, 104)
        local scan = Kit.Button(card, L["AUDIT_BTN_SCAN"], 130, function()
            NS.AuditScanner:Scan()
            page:refresh()
        end)
        scan:SetPoint("TOPLEFT", 14, -42)
        local dump = Kit.Button(card, L["AUDIT_BTN_DUMP"], 130, function() NS.AuditScanner:Dump() end)
        dump:SetPoint("LEFT", scan, "RIGHT", 10, 0)
        Note(card, L["AUDIT_TOOLS_NOTE"], 16, -76, 600)

        local now = Card(parent, L["AUDIT_CARD_PLAN"], y - 114, 120)
        page.plan = Kit.Paragraph(now, "", 600, 12)
        page.plan:SetPoint("TOPLEFT", 16, -42)
    end,
    refresh = function(page)
        local tiles, types, salvation = PlanSummary()
        page.plan:SetText(string.format(L["AUDIT_PLAN_TEXT"], tiles, types, salvation))
    end,
})

---------------------------------------------------------------------------------------------------------------
-- /bwk audit ...
---------------------------------------------------------------------------------------------------------------

area.commandHelp = {
    "|cffffd160/bwk audit|r lock||unlock||reset  " .. L["HELP_AUDIT_TILES"],
    "|cffffd160/bwk audit|r scan||dump||status  " .. L["HELP_AUDIT_TOOLS"],
}

function area.command(args)
    local cmd = args:lower():match("^(%S*)")
    if not Supported() then
        NS:Print(L["AUDIT_CLASS_UNSUPPORTED"], NS.playerClass or "?")
        return
    end
    if cmd == "lock" or cmd == "unlock" then
        NS.AuditBar:SetLocked(cmd == "lock")
    elseif cmd == "reset" then
        NS.AuditBar:ResetPosition()
    elseif cmd == "scan" then
        if NS:IsAreaRunning("audit") then NS.AuditScanner:Scan() else NS:Print(L["AUDIT_NOT_RUNNING"]) end
    elseif cmd == "dump" then
        NS.AuditScanner:Dump()
    elseif cmd == "status" then
        local tiles, types, salvation = PlanSummary()
        NS:Print("%s: %s", L["AREA_AUDIT"], NS:IsAreaRunning("audit") and L["STATUS_ON"] or L["STATUS_OFF"])
        local text = string.format(L["AUDIT_PLAN_TEXT"], tiles, types, salvation):gsub("\n", "\n  ")
        print("  " .. text)
        print("  " .. string.format(L["AUDIT_STATUS_TILES"], cfg().locked and L["AUDIT_LOCKED"] or L["AUDIT_UNLOCKED"],
            math.floor(cfg().scale * 100 + 0.5)))
    else
        for _, line in ipairs(area.commandHelp) do print("  " .. line) end
    end
end
