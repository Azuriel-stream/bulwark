local ADDON_NAME, NS = ...
local L, Kit, Spells = NS.L, NS.Kit, NS.AlertSpells
local C = Kit.C

-- Alerts: failed taunts and threat abilities, loss of control, threat whispers (from TankAlertForever).
local area = NS:RegisterArea({
    key = "alerts",
    order = 1,
    title = L["AREA_ALERTS"],
    desc = L["AREA_ALERTS_DESC"],
    icon = "tab_alerts",
    legacy = "TankAlertForever",
})

NS.DefaultConfig.alerts = {
    forceChannel = "auto",          -- auto, say, party, raid, raid_warning
    announceCC = true,
    announceDisarm = true,
    alertThrottle = 8,              -- seconds between CC/disarm alerts
    quietWhenThreatSolid = true,    -- skip non-taunt alerts while well ahead on threat
    announceThreatWhisper = true,
    threatWhisperThreshold = 90,    -- percent
    whisperThrottle = 15,           -- seconds per player
    onlyTankWhispers = true,
    abilities = {},                 -- [class][ability] = false to stop tracking one
}

local function cfg() return NS.db.alerts end

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

-- Runs a test, or says why it can't while the area isn't running.
local function RunTest(fn)
    if not NS:IsAreaRunning("alerts") then
        NS:Print(L["ALERTS_NOT_RUNNING"])
        return
    end
    fn()
end

local TESTS = {
    miss = function() NS.AbilityAlerts:Simulate() end,
    cc = function() NS.LossOfControl:Simulate("STUNNED") end,
    disarm = function() NS.LossOfControl:Simulate("DISARMED") end,
}

local function TestButton(parent, label, kind, width)
    return Kit.Button(parent, label, width or 120, function()
        RunTest(TESTS[kind] or function() NS.ThreatMonitor:Simulate() end)
    end)
end

---------------------------------------------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "general",
    title = L["PAGE_GENERAL"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_GENERAL"], L["ALERTS_GENERAL_DESC"])

        local threat = Card(parent, L["CARD_THREAT_GATE"], y, 98)
        page.quiet = Kit.Checkbox(threat, L["OPT_QUIET_THREAT"], nil, function(checked)
            cfg().quietWhenThreatSolid = checked
        end)
        page.quiet:SetPoint("TOPLEFT", 12, -38)
        Note(threat, L["OPT_QUIET_THREAT_DESC"], 44, -66)

        local class = Card(parent, L["CARD_YOUR_CLASS"], y - 108, 70)
        page.classText = Kit.Text(class, 12)
        page.classText:SetPoint("TOPLEFT", 16, -42)

        local try = Card(parent, L["CARD_TRY_IT"], y - 188, 102)
        local x = 14
        for _, def in ipairs({ { "BTN_TEST_MISS", "miss" }, { "BTN_TEST_CC", "cc" }, { "BTN_TEST_DISARM", "disarm" },
                                { "BTN_TEST_WHISPER", "whisper" } }) do
            local b = TestButton(try, L[def[1]], def[2], 120)
            b:SetPoint("TOPLEFT", x, -42)
            x = x + 130
        end
        Note(try, L["TEST_NOTE"], 16, -76, 600)
    end,
    refresh = function(page)
        page.quiet:SetChecked(cfg().quietWhenThreatSolid)
        local class = NS.playerClass
        local order = Spells.Order[class]
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
        if order then
            local tracked = 0
            for _, ability in ipairs(order) do
                if NS.AbilityAlerts.IsTracked(class, ability) then tracked = tracked + 1 end
            end
            page.classText:SetText(string.format(L["CLASS_TRACKED"], name, tracked, #order))
        else
            page.classText:SetText(string.format(L["CLASS_NO_ABILITIES"], name))
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "abilities",
    title = L["PAGE_ABILITIES"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_ABILITIES"], L["ALERTS_ABILITIES_DESC"])
        local class = NS.playerClass
        local order = Spells.Order[class] or {}
        local rows = math.max(1, math.ceil(#order / 2))
        local card = Card(parent, L["CARD_TRACKED"], y, 48 + rows * 30)
        page.boxes = {}
        if #order == 0 then
            Note(card, L["NO_ABILITIES"], 16, -44)
        end
        for i, ability in ipairs(order) do
            local data = Spells.Get(class, ability)
            local label = data.isTaunt and (ability .. "  |cff8a8d91" .. L["TAUNT_TAG"] .. "|r") or ability
            local cb = Kit.Checkbox(card, label, data.isTaunt and L["TAUNT_TIP"] or nil, function(checked)
                NS.AbilityAlerts.SetTracked(class, ability, checked)
            end)
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            cb:SetPoint("TOPLEFT", 12 + col * 300, -38 - row * 30)
            page.boxes[ability] = cb
        end
    end,
    refresh = function(page)
        for ability, cb in pairs(page.boxes) do
            cb:SetChecked(NS.AbilityAlerts.IsTracked(NS.playerClass, ability))
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- CC & Disarm
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "cc",
    title = L["PAGE_CC"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_CC"], L["ALERTS_CC_DESC"])
        local card = Card(parent, L["CARD_ANNOUNCE"], y, 150)
        page.cc = Kit.Checkbox(card, L["OPT_ANNOUNCE_CC"], L["OPT_ANNOUNCE_CC_DESC"], function(checked)
            cfg().announceCC = checked
        end)
        page.cc:SetPoint("TOPLEFT", 12, -38)
        page.disarm = Kit.Checkbox(card, L["OPT_ANNOUNCE_DISARM"], L["OPT_ANNOUNCE_DISARM_DESC"], function(checked)
            cfg().announceDisarm = checked
        end)
        page.disarm:SetPoint("TOPLEFT", 312, -38)
        page.throttle = Kit.Slider(card, L["OPT_ALERT_THROTTLE"], 3, 30, 1,
            function(v) return string.format(L["SECONDS"], v) end,
            function(v) cfg().alertThrottle = v end)
        page.throttle:SetPoint("TOPLEFT", 12, -100)

        local try = Card(parent, L["CARD_TRY_IT"], y - 160, 76)
        local cc = TestButton(try, L["BTN_TEST_CC"], "cc")
        cc:SetPoint("TOPLEFT", 14, -42)
        local disarm = TestButton(try, L["BTN_TEST_DISARM"], "disarm")
        disarm:SetPoint("LEFT", cc, "RIGHT", 10, 0)
    end,
    refresh = function(page)
        page.cc:SetChecked(cfg().announceCC)
        page.disarm:SetChecked(cfg().announceDisarm)
        page.throttle:SetValue(cfg().alertThrottle)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Threat whispers
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "threat",
    title = L["PAGE_THREAT"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_THREAT"], L["ALERTS_THREAT_DESC"])
        local card = Card(parent, L["CARD_WHISPERS"], y, 150)
        page.whisper = Kit.Checkbox(card, L["OPT_ENABLE_WHISPERS"], L["OPT_ENABLE_WHISPERS_DESC"], function(checked)
            cfg().announceThreatWhisper = checked
        end)
        page.whisper:SetPoint("TOPLEFT", 12, -38)
        page.tankOnly = Kit.Checkbox(card, L["OPT_ONLY_TANK_WHISPERS"], L["OPT_ONLY_TANK_WHISPERS_DESC"], function(checked)
            cfg().onlyTankWhispers = checked
        end)
        page.tankOnly:SetPoint("TOPLEFT", 312, -38)
        page.threshold = Kit.Slider(card, L["OPT_WHISPER_THRESHOLD"], 50, 100, 1,
            function(v) return string.format("%d%%", v) end,
            function(v) cfg().threatWhisperThreshold = v end)
        page.threshold:SetPoint("TOPLEFT", 12, -100)
        page.whisperThrottle = Kit.Slider(card, L["OPT_WHISPER_THROTTLE"], 5, 30, 1,
            function(v) return string.format(L["SECONDS"], v) end,
            function(v) cfg().whisperThrottle = v end)
        page.whisperThrottle:SetPoint("TOPLEFT", 312, -100)

        local try = Card(parent, L["CARD_TRY_IT"], y - 160, 102)
        local b = TestButton(try, L["BTN_TEST_WHISPER"], "whisper")
        b:SetPoint("TOPLEFT", 14, -42)
        Note(try, L["WHISPER_NOTE"], 16, -76, 600)
    end,
    refresh = function(page)
        page.whisper:SetChecked(cfg().announceThreatWhisper)
        page.tankOnly:SetChecked(cfg().onlyTankWhispers)
        page.threshold:SetValue(cfg().threatWhisperThreshold)
        page.whisperThrottle:SetValue(cfg().whisperThrottle)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Channel (radio rows: Blizzard dropdown menus crashed the client, kb/gotchas.md#menu-crash)
---------------------------------------------------------------------------------------------------------------

local CHANNELS = {
    { key = "auto", label = "CHAN_AUTO", desc = "CHAN_AUTO_DESC" },
    { key = "say", label = "CHAN_SAY", desc = "CHAN_SAY_DESC" },
    { key = "party", label = "CHAN_PARTY", desc = "CHAN_PARTY_DESC" },
    { key = "raid", label = "CHAN_RAID", desc = "CHAN_RAID_DESC" },
    { key = "raid_warning", label = "CHAN_RAID_WARNING", desc = "CHAN_RAID_WARNING_DESC" },
}

NS:AddPage(area.key, {
    key = "channel",
    title = L["PAGE_CHANNEL"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_CHANNEL"], L["ALERTS_CHANNEL_DESC"])
        local card = Card(parent, L["CARD_CHANNEL"], y, 40 + #CHANNELS * 46 + 30)
        page.radios = {}
        for i, ch in ipairs(CHANNELS) do
            local cb = Kit.Checkbox(card, L[ch.label], nil, function()
                cfg().forceChannel = ch.key
                page:refresh()
            end)
            cb:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 46)
            Note(card, L[ch.desc], 44, -62 - (i - 1) * 46, 560)
            page.radios[ch.key] = cb
        end
        page.now = Kit.Text(card, 12, C.goldText)
        page.now:SetPoint("BOTTOMLEFT", 16, 14)
    end,
    refresh = function(page)
        for key, cb in pairs(page.radios) do cb:SetChecked(cfg().forceChannel == key) end
        page.now:SetText(string.format(L["CHANNEL_NOW"], L["CHANNEL_" .. NS.AlertsAnnouncer:GetChannel()]))
    end,
})

---------------------------------------------------------------------------------------------------------------
-- /bwk alerts ...
---------------------------------------------------------------------------------------------------------------

local function OnOff(v) return v and L["STATUS_ON"] or L["STATUS_OFF"] end

area.commandHelp = {
    "|cffffd160/bwk alerts test|r miss||cc||disarm||whisper [name]  " .. L["HELP_ALERTS_TEST"],
    "|cffffd160/bwk alerts status|r  " .. L["HELP_ALERTS_STATUS"],
}

function area.command(args)
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "test" then
        local kind, name = rest:match("^(%S*)%s*(.-)$")
        kind = kind:lower()
        if TESTS[kind] then
            RunTest(TESTS[kind])
        elseif kind == "whisper" then
            RunTest(function() NS.ThreatMonitor:Simulate(name ~= "" and name or nil) end)
        else
            NS:Print(L["ALERTS_TEST_USAGE"])
        end
    elseif cmd == "status" then
        local c = cfg()
        NS:Print(L["ALERTS_STATUS"], L["AREA_ALERTS"], OnOff(NS:IsAreaRunning("alerts")))
        print("  " .. string.format(L["STATUS_CHANNEL"], L["CHANNEL_" .. NS.AlertsAnnouncer:GetChannel()], c.forceChannel))
        print("  " .. string.format(L["STATUS_CC"], OnOff(c.announceCC), OnOff(c.announceDisarm), c.alertThrottle))
        print("  " .. string.format(L["STATUS_QUIET"], OnOff(c.quietWhenThreatSolid)))
        print("  " .. string.format(L["STATUS_WHISPER"], OnOff(c.announceThreatWhisper), c.threatWhisperThreshold))
    else
        for _, line in ipairs(area.commandHelp) do print("  " .. line) end
    end
end
