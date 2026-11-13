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
    consumablesInGroup = true,  -- check consumables in a party or raid
    consumablesSolo = false,    -- check consumables when ungrouped (both on = always)
    checkHealthstone = true,
    checkDebuffs = true,
    checkUnwanted = true,
    checkDefenseSkill = true,   -- tile: defense skill below the level cap (groups only)
    checkShield = true,         -- tile: tanking (Defensive Stance / Righteous Fury) without a shield
    checkDurability = true,     -- tile: an equipped item at or below durabilityWarn %
    durabilityWarn = 25,
    gratitude = true,           -- whisper the caster when a requested buff arrives
    raceVoice = true,           -- requests and thank-yous in the player's race voice (Voices.lua); off = Neutral
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
                if def.key == "checkConsumables" then page:refresh() end -- greys the Consumables card
                Rescan()
            end)
            cb:SetPoint("TOPLEFT", 12 + def.col * 300, -38 - math.floor((i - 1) / 2) * 32)
            page.checks[def.key] = cb
        end

        -- Consumables: when (in a group / solo, independent: both = always), then "+ Elixir" / "+ Flask" on top of
        -- food, at most one (radio-like checkboxes; no dropdowns, kb/gotchas.md#menu-crash). Greyed out while the
        -- Consumables check above is off (values kept).
        local cons = Card(parent, L["AUDIT_CARD_CONSUMABLES"], y - 150, 130)
        page.consumablesWhen = {}
        for i, opt in ipairs({ { key = "consumablesInGroup", label = "AUDIT_CONS_GROUP" },
                               { key = "consumablesSolo", label = "AUDIT_CONS_SOLO" } }) do
            local cb = Kit.Checkbox(cons, L[opt.label], L["AUDIT_CONS_WHEN_DESC"], function(checked)
                cfg()[opt.key] = checked
                Rescan()
            end)
            cb:SetPoint("TOPLEFT", 12 + (i - 1) * 300, -38)
            page.consumablesWhen[opt.key] = cb
        end
        page.consumables = {}
        for i, opt in ipairs({ { level = 2, label = "AUDIT_CONS_ELIXIR" }, { level = 3, label = "AUDIT_CONS_FLASK" } }) do
            local cb = Kit.Checkbox(cons, L[opt.label], L["AUDIT_CONS_DESC"], function(checked)
                cfg().consumableLevel = checked and opt.level or 1
                page:refresh()
                Rescan()
            end)
            cb:SetPoint("TOPLEFT", 12 + (i - 1) * 300, -70)
            page.consumables[opt.level] = cb
        end
        page.consNote = Note(cons, L["AUDIT_CONS_DESC"], 16, -100, 600)

        local thanks = Card(parent, L["AUDIT_CARD_THANKS"], y - 290, 70)
        page.gratitude = Kit.Checkbox(thanks, L["AUDIT_OPT_GRATITUDE"], L["AUDIT_OPT_GRATITUDE_DESC"], function(checked)
            cfg().gratitude = checked
        end)
        page.gratitude:SetPoint("TOPLEFT", 12, -38)
        local _, raceName = NS.AuditVoices.PlayerRace()
        page.raceVoice = Kit.Checkbox(thanks, L["AUDIT_OPT_RACE_VOICE"],
            string.format(L["AUDIT_OPT_RACE_VOICE_DESC"], raceName or L["AUDIT_VOICE_UNKNOWN"]), function(checked)
            cfg().raceVoice = checked
        end)
        page.raceVoice:SetPoint("TOPLEFT", 312, -38)
    end,
    refresh = function(page)
        for key, cb in pairs(page.checks) do cb:SetChecked(cfg()[key]) end
        local consOn = cfg().checkConsumables and true or false
        for key, cb in pairs(page.consumablesWhen) do
            cb:SetChecked(cfg()[key])
            cb:SetActive(consOn)
        end
        for level, cb in pairs(page.consumables) do
            cb:SetChecked(cfg().consumableLevel == level)
            cb:SetActive(consOn)
        end
        Kit.SetTextColor(page.consNote, consOn and C.muted or C.disabled)
        page.gratitude:SetChecked(cfg().gratitude)
        page.raceVoice:SetChecked(cfg().raceVoice)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Gear: tank gear warning tiles (Utilities feature 8; user 2026-11-12: Audit tiles)
---------------------------------------------------------------------------------------------------------------

local GEAR_CHECKS = {
    { key = "checkDefenseSkill", text = "AUDIT_OPT_DEFENSE_SKILL" },
    { key = "checkShield", text = "AUDIT_OPT_SHIELD" },
    { key = "checkDurability", text = "AUDIT_OPT_DURABILITY" },
}

NS:AddPage(area.key, {
    key = "gear",
    title = L["PAGE_GEAR"],
    build = function(page, parent)
        local y = Header(parent, L["PAGE_GEAR"], L["AUDIT_GEAR_DESC"])
        local card = Card(parent, L["AUDIT_CARD_GEAR"], y, 40 + #GEAR_CHECKS * 50 + 70)
        page.checks = {}
        for i, def in ipairs(GEAR_CHECKS) do
            local cb = Kit.Checkbox(card, L[def.text], nil, function(checked)
                cfg()[def.key] = checked
                page:refresh()
                Rescan()
            end)
            cb:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 50)
            Note(card, L[def.text .. "_DESC"], 44, -62 - (i - 1) * 50, 580)
            page.checks[def.key] = cb
        end
        page.durability = Kit.Slider(card, L["AUDIT_OPT_DURABILITY_WARN"], 10, 50, 5,
            function(v) return string.format("%d%%", v) end,
            function(v) cfg().durabilityWarn = v; Rescan() end)
        page.durability:SetPoint("TOPLEFT", 12, -38 - #GEAR_CHECKS * 50 - 22)
    end,
    refresh = function(page)
        for key, cb in pairs(page.checks) do cb:SetChecked(cfg()[key]) end
        page.durability:SetValue(cfg().durabilityWarn or 25)
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
    "|cffffd160/bwk audit|r scan||dump||status||voice  " .. L["HELP_AUDIT_TOOLS"],
}

-- /bwk audit voice: the voice in use and the message each current request tile would send (printed, not sent).
local function VoicePreview()
    local Voices = NS.AuditVoices
    local _, key = Voices.Current()
    local _, raceName = Voices.PlayerRace()
    NS:Print(L["AUDIT_VOICE_STATUS"], raceName or "?", key == "NEUTRAL" and L["AUDIT_VOICE_NEUTRAL"] or key)
    local shown = 0
    for _, item in ipairs((NS.AuditScanner.plan or {}).tiles or {}) do
        if item.action and item.action.type == "request" then
            if shown == 0 then print("  " .. L["AUDIT_VOICE_PREVIEW"]) end
            shown = shown + 1
            print("  - " .. NS.AuditRequests:BuildMessage(item))
        end
    end
    for dtype, action in pairs((NS.AuditScanner.plan or {}).dispelActions or {}) do
        if action.type == "request" then
            if shown == 0 then print("  " .. L["AUDIT_VOICE_PREVIEW"]) end
            shown = shown + 1
            print("  - " .. NS.AuditRequests:BuildMessage({ key = "DEBUFF", kind = "debuff", dispelType = dtype }))
        end
    end
    if shown == 0 then print("  " .. L["AUDIT_VOICE_NONE"]) end
    print("  - " .. Voices.Thanks(Utils.SpellChatName(1243), "Thalindra"))
end

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
    elseif cmd == "voice" then
        VoicePreview()
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
