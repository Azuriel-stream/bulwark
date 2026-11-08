-- Alerts area (ported from TankAlertForever): failure alerts + threat gate, loss of control, whispers,
-- channels, the area switch, pages and commands.
return function(sim, t)
    local NS = sim.env.Bulwark
    local cfg = NS.db.alerts
    t.ok(NS:IsAreaRunning("alerts"), "Alerts runs at login")
    t.eq(cfg.forceChannel, "auto", "default channel auto")
    t.eq(cfg.quietWhenThreatSolid, true, "quiet-while-solid on by default")

    local function newChat(fn)
        local before = #sim.chat
        fn()
        sim:Advance(0.01)   -- sends happen on the next frame, outside the event handler
        local lines = {}
        for i = before + 1, #sim.chat do lines[#lines + 1] = sim.chat[i] end
        return lines
    end

    -- Cast on the target, then the target reports an avoidance.
    local function castAndAvoid(spellID, action)
        sim:Advance(2)   -- past the per-ability 1 s throttle and the 1.5 s cast window
        return newChat(function()
            sim:Fire("UNIT_SPELLCAST_SENT", "player", "Defias Pillager", "Cast-1", spellID)
            sim:Fire("UNIT_COMBAT", "target", action, "", 0, 1)
        end)
    end

    -- Party default: a Sunder dodge goes to party chat, plain spell name, raid icon token, target name.
    sim.units.player.threatLead = 1
    local lines = castAndAvoid(7386, "DODGE")
    t.eq(#lines, 1, "Sunder dodge announced")
    t.eq(lines[1].channel, "PARTY", "auto = party in a party")
    t.ok(lines[1].msg:find("[Sunder Armor] DODGED on {rt8} Defias Pillager", 1, true), "message text: " .. lines[1].msg)
    t.ok(not lines[1].msg:find("|H", 1, true), "no spell link (kb/gotchas.md#spell-link-chat)")
    t.eq(#castAndAvoid(7386, "WOUND"), 0, "a hit is not announced")
    t.eq(#castAndAvoid(78, "DODGE"), 0, "untracked spell not announced")

    -- Threat gate (ported): solid lead silences non-taunts in combat; taunts always go out.
    sim:EnterCombat()
    sim.units.player.threatLead = 0
    t.eq(#castAndAvoid(7386, "DODGE"), 0, "Sunder dodge quiet while threat is solid")
    local taunt = castAndAvoid(355, "RESIST")
    t.eq(#taunt, 1, "Taunt resist announced even with solid threat")
    t.ok(taunt[1].msg:find("RESISTED"), "Taunt alert says RESISTED")
    sim.units.player.threatLead = 3
    t.eq(#castAndAvoid(23922, "MISS"), 1, "announced when not top on threat")
    sim.units.player.threatLead = 0
    sim.units.target.secretThreatState = true
    t.eq(#castAndAvoid(7386, "DODGE"), 1, "announced when the lead state is secret")
    sim.units.target.secretThreatState = nil
    cfg.quietWhenThreatSolid = false
    t.eq(#castAndAvoid(7386, "DODGE"), 1, "announced with the option off")
    cfg.quietWhenThreatSolid = true
    NS.db.debug = true
    local printed = #sim.output
    t.eq(#castAndAvoid(7386, "DODGE"), 0, "still quiet with the debug trace on")
    t.contains({ unpack(sim.output, printed + 1) }, "not announced", "debug trace names the skipped alert")
    NS.db.debug = false

    -- Immune via UI error.
    sim.units.player.threatLead = 2
    sim:Advance(2)
    lines = newChat(function()
        sim:Fire("UNIT_SPELLCAST_SENT", "player", "Defias Pillager", "Cast-2", 355)
        sim:Fire("UI_ERROR_MESSAGE", 51, "Target is immune")
    end)
    t.eq(#lines, 1, "immune announced")
    t.ok(lines[1].msg:find("IMMUNE"), "says IMMUNE")
    sim:LeaveCombat()

    -- Loss of control through the LOC event: payload is (unit, index) [docs].
    sim:Advance(10)
    sim.loc[1] = { locType = "STUN_MECHANIC", spellID = 853, displayText = "Stunned" }
    -- Sent on the next frame, not from inside the LOC event handler ([in-game]: sends from inside it were blocked).
    lines = newChat(function()
        local before = #sim.chat
        sim:Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
        t.eq(#sim.chat, before, "nothing sent from inside the LOC event handler")
    end)
    t.eq(#lines, 1, "stun announced from the LOC event")
    t.ok(lines[1].msg:find("STUNNED"), "says STUNNED")
    t.eq(#newChat(function() sim:Fire("LOSS_OF_CONTROL_ADDED", "player", 1) end), 0, "same stun not repeated")
    sim.loc = {}
    sim:Fire("LOSS_OF_CONTROL_UPDATE", "player")
    sim:Advance(10)
    sim.loc[1] = { locType = "FEAR_MECHANIC", spellID = 5782 }
    t.eq(#newChat(function() sim:Fire("LOSS_OF_CONTROL_ADDED", "target", 1) end), 0, "another unit's LOC ignored")
    sim.loc = {}

    -- UI-error fallback, throttle, disarm needs a weapon.
    sim:Advance(10)
    t.eq(#newChat(function() sim:Fire("UI_ERROR_MESSAGE", 51, "Can't do that while feared") end), 1, "fear from UI error")
    sim:Fire("LOSS_OF_CONTROL_UPDATE", "player")
    t.eq(#newChat(function() sim:Fire("UI_ERROR_MESSAGE", 51, "Can't do that while stunned") end), 0, "throttled within 8 s")
    sim:Advance(10)
    t.eq(#newChat(function() sim:Fire("UI_ERROR_MESSAGE", 51, "You are disarmed") end), 1, "disarm with a weapon")
    cfg.announceDisarm = false
    sim:Fire("LOSS_OF_CONTROL_UPDATE", "player")
    sim:Advance(10)
    t.eq(#newChat(function() sim:Fire("UI_ERROR_MESSAGE", 51, "You are disarmed") end), 0, "disarm option off")
    cfg.announceDisarm = true

    -- Threat whispers: in combat, a member over the threshold gets one whisper per throttle window.
    sim.units.player.threat = { true, 3, 100, 100, 10000 }
    lines = newChat(function()
        sim:EnterCombat()
        sim:Advance(1.1)
    end)
    t.eq(#lines, 1, "one whisper")
    t.eq(lines[1].channel, "WHISPER", "whisper channel")
    t.eq(lines[1].target, "Lumen Brightwater", "whispers the member by full name")
    t.ok(lines[1].msg:find("^%[Bulwark%] Careful! You are at 95%% threat"), "whisper text: " .. lines[1].msg)
    t.eq(#newChat(function() sim:Advance(3) end), 0, "throttled per player")
    sim:LeaveCombat()

    -- Addon chat restricted (boss fight, restricted map): nothing is sent (it would be blocked), the alert shows
    -- locally; whispers are skipped. [in-game 2026-11-08: a stun alert to party was blocked, ADDON_ACTION_BLOCKED]
    sim.chatRestricted = true
    sim:EnterCombat()
    sim.units.player.threatLead = 3
    printed = #sim.output
    t.eq(#castAndAvoid(355, "RESIST"), 0, "restricted: nothing sent")
    t.contains({ unpack(sim.output, printed + 1) }, "RESISTED", "restricted: shown locally")
    t.contains({ unpack(sim.output, printed + 1) }, "couldn't go to Party.*Chat", "restricted: says why, naming the restriction")
    sim:Advance(10)
    t.eq(#newChat(function() sim:Fire("UI_ERROR_MESSAGE", 51, "Can't do that while stunned") end), 0, "restricted: stun not sent")
    t.eq(#newChat(function() sim:Advance(2) end), 0, "restricted: no threat whispers")
    t.eq(#sim.violations, 0, "restricted: no blocked actions")
    sim:LeaveCombat()
    sim.chatRestricted = false
    sim:Fire("LOSS_OF_CONTROL_UPDATE", "player")

    -- No scan tooltip for secret names (it tainted Blizzard's tooltip code in combat, [in-game] 2026-11-08).
    sim:EnterCombat()
    t.eq(sim.env.Bulwark.Utils.GetSafeUnitName("target", "fallback"), "fallback", "secret target name: fallback")
    sim:LeaveCombat()
    t.eq(sim.env.Bulwark_ScanTooltip, nil, "no scan tooltip created")

    -- Solo: alerts are local lines, not Say.
    sim.group = "none"
    t.eq(NS.AlertsAnnouncer:GetChannel(), "SAY", "solo resolves to Say")
    printed = #sim.output
    lines = castAndAvoid(7386, "PARRY")
    t.eq(#lines, 0, "solo: nothing sent to chat")
    t.contains({ unpack(sim.output, printed + 1) }, "PARRIED", "solo: printed locally")
    sim.group = "party"

    -- Area off: no events, no alerts; on again: back.
    NS:SetAreaEnabled("alerts", false)
    t.eq(#castAndAvoid(7386, "DODGE"), 0, "nothing while Alerts is off")
    printed = #sim.output
    sim:Slash("/bwk alerts test miss")
    t.contains({ unpack(sim.output, printed + 1) }, "off or waiting", "test says Alerts is off")
    NS:SetAreaEnabled("alerts", true)
    t.eq(#castAndAvoid(7386, "DODGE"), 1, "alerts back after switching on")

    -- Commands.
    sim:Advance(2)
    t.eq(#newChat(function() sim:Slash("/bwk alerts test miss") end), 1, "/bwk alerts test miss sends a test")
    sim:Advance(10)
    t.eq(#newChat(function() sim:Slash("/bwk alerts test cc") end), 1, "/bwk alerts test cc")
    lines = newChat(function() sim:Slash("/bwk alerts test whisper Some Body") end)
    t.eq(lines[1] and lines[1].target, "Some Body", "test whisper keeps the name's case")
    printed = #sim.output
    sim:Slash("/bwk alerts status")
    t.contains({ unpack(sim.output, printed + 1) }, "Channel: Party", "status shows the channel")

    -- Pages write the settings.
    local area = NS:GetArea("alerts")
    local function page(key)
        for _, p in ipairs(area.pages) do if p.key == key then NS.Window:Select("alerts", key); return p end end
    end
    local general = page("general")
    general.quiet:Click()
    t.eq(cfg.quietWhenThreatSolid, false, "quiet checkbox")
    general.quiet:Click()
    local abilities = page("abilities")
    t.ok(abilities.boxes["Sunder Armor"], "warrior abilities listed")
    abilities.boxes["Sunder Armor"]:Click()
    t.eq(cfg.abilities.WARRIOR["Sunder Armor"], false, "untracking saved")
    t.eq(#castAndAvoid(7386, "DODGE"), 0, "untracked Sunder not announced")
    abilities.boxes["Sunder Armor"]:Click()
    local cc = page("cc")
    cc.throttle.Slider:SetValue(12)
    t.eq(cfg.alertThrottle, 12, "throttle slider")
    cc.cc:Click()
    t.eq(cfg.announceCC, false, "CC checkbox")
    local threat = page("threat")
    threat.threshold.Slider:SetValue(80)
    t.eq(cfg.threatWhisperThreshold, 80, "threshold slider")
    threat.tankOnly:Click()
    t.eq(cfg.onlyTankWhispers, false, "tank-only checkbox")
    local channel = page("channel")
    channel.radios.raid:Click()
    t.eq(cfg.forceChannel, "raid", "channel radio saved")
    local selected = 0
    for _, cb in pairs(channel.radios) do if cb:GetChecked() then selected = selected + 1 end end
    t.eq(selected, 1, "exactly one channel selected")
    channel.radios.raid:Click()
    t.ok(channel.radios.raid:GetChecked(), "clicking the selected channel keeps it")
    t.ok(channel.now:GetText():find("Party"), "raid setting in a party resolves to Party")

    -- A class without tank abilities gets a note, no checkboxes.
    local s2 = t.fresh(function(s) s.units.player.class = "MAGE" end)
    s2.env.Bulwark.Window:Open("alerts", "abilities")
    local p2
    for _, p in ipairs(s2.env.Bulwark:GetArea("alerts").pages) do if p.key == "abilities" then p2 = p end end
    t.ok(next(p2.boxes) == nil, "no ability checkboxes for a mage")
end
