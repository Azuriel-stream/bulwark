local ADDON_NAME, NS = ...
local L, Kit, D, Utils = NS.L, NS.Kit, NS.AuditData, NS.Utils
local C = Kit.C

-- Audit: pre-pull tiles for missing buffs, consumables and dispellable debuffs; buff requests and
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
    checkScrolls = true,        -- scroll tiles for buffs nobody in the group gives (part of Consumables)
    checkHealthstone = true,
    checkDebuffs = true,
    hideResting = true,         -- no buff/consumable tiles in a city or inn (gear warnings and debuffs stay)
    checkDefenseSkill = true,   -- tile: defense skill below the level cap (groups only)
    checkShield = true,         -- tile: tanking (Defensive Stance / Righteous Fury) without a shield
    checkDurability = true,     -- tile: an equipped item at or below durabilityWarn %
    durabilityWarn = 25,
    gratitude = true,           -- whisper the caster when a requested buff arrives
    raceVoice = true,           -- requests and thank-yous in the player's race voice (Voices.lua); off = Neutral
    manaBreak = true,           -- mana break prompts, 5-man groups only (ManaBreak.lua)
    manaSelf = true,            --   your own mana: a clickable tile
    manaHealer = true,          --   the healer's mana: a prompt that fades in by itself (secret value)
    manaThreshold = 40,         --   show below this %
    manaHealerPick = "",        --   first name of the healer when the group has no role and no single healing class
    carrot = true,              -- Carrot on a Stick tile: put it on when mounted, swap it off on foot (Carrot.lua)
    carrotSlot = 14,            --   the trinket slot it goes into (13 or 14)
    watchSound = true,          -- in-combat sound when Battle Shout / Righteous Fury is about to fade
    watchWarnSeconds = 15,
    watchDurations = {},        -- [spellID] = real duration learned out of combat
    selfStrength = {},          -- [playerGUID] = { [spellID] = your own buff's value (talents included), learned OOC }
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
    NS.AuditManaBreak:SetWindowPreview(shown and areaKey == "audit")
    NS.AuditCarrot:SetWindowPreview(shown and areaKey == "audit")
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

        -- Consumables: when (in a group / solo, independent: both = always), then what on top of food: nothing, an
        -- elixir or a flask (our own dropdown, Kit.Dropdown; user 2026-11-14: was two checkboxes acting as one
        -- choice). Greyed out while the Consumables check above is off (values kept).
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
        page.consLevel = Kit.Dropdown(cons, 220, function()
            return { { key = 1, label = L["AUDIT_CONS_LEVEL_1"] }, { key = 2, label = L["AUDIT_CONS_LEVEL_2"] },
                     { key = 3, label = L["AUDIT_CONS_LEVEL_3"] } }
        end, function() return cfg().consumableLevel or 1 end, function(level)
            cfg().consumableLevel = level
            Rescan()
        end)
        page.consLevel:SetPoint("TOPLEFT", 16, -70)
        Kit.Tooltip(page.consLevel, L["AUDIT_CARD_CONSUMABLES"], L["AUDIT_CONS_DESC"])
        page.scrolls = Kit.Checkbox(cons, L["AUDIT_CONS_SCROLLS"], L["AUDIT_CONS_SCROLLS_DESC"], function(checked)
            cfg().checkScrolls = checked
            Rescan()
        end)
        page.scrolls:SetPoint("TOPLEFT", 312, -68)
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
        page.consLevel:Refresh()
        page.consLevel:SetActive(consOn)
        page.scrolls:SetChecked(cfg().checkScrolls)
        page.scrolls:SetActive(consOn)
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

        -- Carrot on a Stick (Carrot.lua)
        local carrot = Card(parent, L["AUDIT_CARD_CARROT"], y - (40 + #GEAR_CHECKS * 50 + 70) - 10, 112)
        page.carrot = Kit.Checkbox(carrot, L["AUDIT_OPT_CARROT"], nil, function(checked)
            cfg().carrot = checked
            page:refresh()
            NS.AuditCarrot:Changed()
        end)
        page.carrot:SetPoint("TOPLEFT", 12, -38)
        local slotLabel = Kit.Text(carrot, 12, C.text)
        slotLabel:SetPoint("TOPLEFT", 400, -44)
        slotLabel:SetText(L["AUDIT_CARROT_SLOT"])
        page.carrotSlot = Kit.Dropdown(carrot, 170, function()
            return { { key = 13, label = L["CARROT_SLOT_13"] }, { key = 14, label = L["CARROT_SLOT_14"] } }
        end, function() return NS.AuditCarrot.ChosenSlot() end, function(key)
            cfg().carrotSlot = key
            NS.AuditCarrot:Changed()
        end)
        page.carrotSlot:SetPoint("TOPLEFT", 440, -38)
        Note(carrot, L["AUDIT_OPT_CARROT_DESC"], 44, -66, 580)
    end,
    refresh = function(page)
        for key, cb in pairs(page.checks) do cb:SetChecked(cfg()[key]) end
        page.durability:SetValue(cfg().durabilityWarn or 25)
        page.carrot:SetChecked(cfg().carrot)
        page.carrotSlot:SetActive(cfg().carrot)
        page.carrotSlot:Refresh()
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
-- Mana break (5-man groups; ManaBreak.lua)
---------------------------------------------------------------------------------------------------------------

local function ClassColored(name, class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
    return name
end

-- Healer list: Automatic, then the party (class coloured); a picked player who left stays listed, grey.
local function HealerOptions()
    local opts = { { key = "", label = L["AUDIT_MANA_AUTO"] } }
    local pick, listed = cfg().manaHealerPick or "", false
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party" .. i
        local name = UnitExists(unit) and NS.AuditVoices.FirstName(unit)
        if name then
            local ok, _, class = pcall(UnitClass, unit)
            opts[#opts + 1] = { key = name, label = ClassColored(name, ok and Utils.SafeString(class, nil) or nil) }
            if name == pick then listed = true end
        end
    end
    if pick ~= "" and not listed then opts[#opts + 1] = { key = pick, label = "|cff888888" .. pick .. "|r" } end
    return opts
end

local function HealerNow()
    local MB = NS.AuditManaBreak
    local _, name, how = MB.FindHealer()
    if not MB.FiveMan() then return L["AUDIT_MANA_NOW_NOGROUP"] end
    if not name then return L["AUDIT_MANA_NOW_NONE"] end
    return string.format("%s (%s)", name, L["MANA_HOW_" .. how])
end

NS:AddPage(area.key, {
    key = "mana",
    title = L["PAGE_MANA"],
    build = function(page, parent)
        local MB = NS.AuditManaBreak
        local function Changed() page:refresh(); MB:Changed() end
        local y = Header(parent, L["PAGE_MANA"], L["AUDIT_MANA_DESC"])
        local card = Card(parent, L["AUDIT_CARD_MANA"], y, 238)
        page.on = Kit.Checkbox(card, L["AUDIT_OPT_MANA"], L["AUDIT_OPT_MANA_DESC"], function(checked)
            cfg().manaBreak = checked
            Changed()
        end)
        page.on:SetPoint("TOPLEFT", 12, -38)
        page.threshold = Kit.Slider(card, L["AUDIT_OPT_MANA_THRESHOLD"], 10, 80, 5,
            function(v) return string.format("%d%%", v) end,
            function(v) cfg().manaThreshold = v; MB:Changed() end)
        page.threshold:SetPoint("TOPLEFT", 312, -58)

        page.self = Kit.Checkbox(card, L["AUDIT_OPT_MANA_SELF"], nil, function(checked)
            cfg().manaSelf = checked
            Changed()
        end)
        page.self:SetPoint("TOPLEFT", 12, -84)
        page.selfNote = Note(card, L["AUDIT_OPT_MANA_SELF_DESC"], 44, -108, 580)

        page.healer = Kit.Checkbox(card, L["AUDIT_OPT_MANA_HEALER"], nil, function(checked)
            cfg().manaHealer = checked
            Changed()
        end)
        page.healer:SetPoint("TOPLEFT", 12, -138)
        page.healerNote = Note(card, L["AUDIT_OPT_MANA_HEALER_DESC"], 44, -162, 580)

        page.pickLabel = Kit.Text(card, 12, C.goldText)
        page.pickLabel:SetPoint("TOPLEFT", 44, -210)
        page.pickLabel:SetText(L["AUDIT_MANA_HEALER_LABEL"])
        page.pick = Kit.Dropdown(card, 160, HealerOptions, function() return cfg().manaHealerPick or "" end,
            function(name)
                cfg().manaHealerPick = name
                Changed()
            end)
        page.pick:SetPoint("TOPLEFT", 110, -202)
        Kit.Tooltip(page.pick, L["AUDIT_MANA_HEALER_LABEL"], L["AUDIT_MANA_PICK_DESC"])
        page.now = Kit.Text(card, 12, C.muted)
        page.now:SetPoint("LEFT", page.pick, "RIGHT", 12, 0)

        local key = Card(parent, L["AUDIT_CARD_MANA_KEY"], y - 248, 128)
        page.keyText = Kit.Text(key, 12)
        page.keyText:SetPoint("TOPLEFT", 16, -44)
        local previewBtn = Kit.Button(key, L["AUDIT_MANA_PREVIEW_BTN"], 160, function()
            NS:Print(L["AUDIT_MANA_PREVIEW_HEAD"])
            print("  - " .. NS.AuditVoices.ManaBreak("self"))
            print("  - " .. NS.AuditVoices.ManaBreak("healer", MB.healerName or L["MANA_SAMPLE_HEALER"]))
        end)
        previewBtn:SetPoint("TOPLEFT", 14, -62)
        Note(key, L["AUDIT_MANA_KEY_NOTE"], 186, -66, 440)
        Note(key, L["AUDIT_MANA_NOTE"], 16, -98, 600)
    end,
    refresh = function(page)
        local c, on = cfg(), cfg().manaBreak and true or false
        page.on:SetChecked(c.manaBreak)
        page.threshold:SetValue(c.manaThreshold or 40)
        page.self:SetChecked(c.manaSelf)
        page.healer:SetChecked(c.manaHealer)
        page.self:SetActive(on)
        page.healer:SetActive(on)
        Kit.SetTextColor(page.selfNote, on and C.muted or C.disabled)
        Kit.SetTextColor(page.healerNote, on and C.muted or C.disabled)
        page.pick:Refresh()
        page.pick:SetActive(on and c.manaHealer and true or false)
        page.now:SetText(string.format(L["AUDIT_MANA_NOW"], HealerNow()))
        page.keyText:SetText(NS.AuditManaBreak.KeyHint())
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
        local card = Card(parent, L["AUDIT_CARD_TILES"], y, 174)
        page.lock = Kit.Checkbox(card, L["AUDIT_OPT_LOCK"], L["AUDIT_OPT_LOCK_DESC"], function(checked)
            NS.AuditBar:SetLocked(checked, true)
        end)
        page.lock:SetPoint("TOPLEFT", 12, -38)
        local reset = Kit.Button(card, L["AUDIT_BTN_RESET"], 150, function() NS.AuditBar:ResetPosition() end)
        reset:SetPoint("TOPLEFT", 312, -40)
        local function Percent(v) return string.format("%d%%", v) end
        page.scale = Kit.Slider(card, L["AUDIT_OPT_SCALE"], 50, 200, 10, Percent,
            function(v) NS.AuditBar:SetScale(v / 100) end)
        page.scale:SetPoint("TOPLEFT", 12, -96)
        page.debuffScale = Kit.Slider(card, L["AUDIT_OPT_DEBUFF_SCALE"], 50, 200, 10, Percent,
            function(v) NS.AuditBar:SetDebuffScale(v / 100) end)
        page.debuffScale:SetPoint("TOPLEFT", 312, -96)
        -- When tiles show (user 2026-11-14: belongs with the tiles, not with the checks)
        page.hideResting = Kit.Checkbox(card, L["AUDIT_OPT_HIDE_RESTING"], L["AUDIT_OPT_HIDE_RESTING_DESC"], function(checked)
            cfg().hideResting = checked
            Rescan()
        end)
        page.hideResting:SetPoint("TOPLEFT", 12, -138)
        Note(parent, L["AUDIT_PREVIEW_NOTE"], 0, y - 186, 640)
    end,
    refresh = function(page)
        page.lock:SetChecked(cfg().locked)
        page.hideResting:SetChecked(cfg().hideResting)
        page.scale:SetValue(math.floor(cfg().scale * 100 + 0.5))
        page.debuffScale:SetValue(math.floor((cfg().debuffScale or cfg().scale) * 100 + 0.5))
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
    return #names > 0 and table.concat(names, ", ") or "-", #types > 0 and table.concat(types, ", ") or "-"
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
        local tiles, types = PlanSummary()
        page.plan:SetText(string.format(L["AUDIT_PLAN_TEXT"], tiles, types))
    end,
})

---------------------------------------------------------------------------------------------------------------
-- /bwk audit ...
---------------------------------------------------------------------------------------------------------------

area.commandHelp = {
    "|cffffd160/bwk audit|r lock||unlock||reset  " .. L["HELP_AUDIT_TILES"],
    "|cffffd160/bwk audit|r scan||dump||status||voice  " .. L["HELP_AUDIT_TOOLS"],
    "|cffffd160/bwk audit mana|r [self||healer||status]  " .. L["HELP_AUDIT_MANA"],
    "|cffffd160/bwk audit carrot|r  " .. L["HELP_AUDIT_CARROT"],
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
    print("  - " .. Voices.ManaBreak("self"))
    print("  - " .. Voices.ManaBreak("healer", NS.AuditManaBreak.healerName or "Thalindra"))
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
    elseif cmd == "mana" then
        local sub = args:lower():match("^%S+%s+(%S+)")
        if sub == "status" then
            NS.AuditManaBreak.Status()
        elseif not NS:IsAreaRunning("audit") then
            NS:Print(L["AUDIT_NOT_RUNNING"])
        else
            NS.AuditManaBreak.Announce((sub == "self" or sub == "healer") and sub or nil)
        end
    elseif cmd == "carrot" then
        NS.AuditCarrot.Status()
    elseif cmd == "status" then
        local tiles, types = PlanSummary()
        NS:Print("%s: %s", L["AREA_AUDIT"], NS:IsAreaRunning("audit") and L["STATUS_ON"] or L["STATUS_OFF"])
        local text = string.format(L["AUDIT_PLAN_TEXT"], tiles, types):gsub("\n", "\n  ")
        print("  " .. text)
        print("  " .. string.format(L["AUDIT_STATUS_TILES"], cfg().locked and L["AUDIT_LOCKED"] or L["AUDIT_UNLOCKED"],
            math.floor(cfg().scale * 100 + 0.5), math.floor((cfg().debuffScale or cfg().scale) * 100 + 0.5)))
    else
        for _, line in ipairs(area.commandHelp) do print("  " .. line) end
    end
end
