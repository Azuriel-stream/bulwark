-- Area switches: module lifecycle, combat refusal, legacy addon guard, Settings > Areas page.
return function(sim, t)
    local NS = sim.env.Bulwark

    -- Every area starts on.
    for _, key in ipairs({ "alerts", "audit", "marking" }) do
        t.eq(NS:AreaStatus(key), "on", key .. " on by default")
        t.ok(NS:IsAreaRunning(key), key .. " running after login")
    end
    t.ok(NS:IsAreaEnabled("settings"), "settings is always on")
    t.ok(not NS:SetAreaEnabled("settings", false), "settings has no switch")

    -- An area's modules follow its switch; other areas' modules don't.
    local calls = { on = 0, off = 0, other = 0 }
    local mod = NS:RegisterModule("TestAlertsModule", "alerts")
    function mod:OnEnable() calls.on = calls.on + 1 end
    function mod:OnDisable() calls.off = calls.off + 1 end
    local other = NS:RegisterModule("TestAuditModule", "audit")
    function other:OnDisable() calls.other = calls.other + 1 end

    t.ok(NS:SetAreaEnabled("alerts", false), "switch moved")
    t.eq(NS.db.areas.alerts.enabled, false, "off is saved")
    t.eq(calls.off, 1, "area off disables its modules")
    t.eq(calls.other, 0, "other areas untouched")
    t.ok(not NS:IsAreaRunning("alerts"), "alerts stopped")
    NS:SetAreaEnabled("alerts", false)
    t.eq(calls.off, 1, "switching off twice disables once")
    NS:SetAreaEnabled("alerts", true)
    t.eq(calls.on, 1, "area on enables its modules")

    -- Not in combat (areas own secure frames).
    sim:EnterCombat()
    t.ok(not NS:SetAreaEnabled("alerts", false), "refused in combat")
    t.eq(NS.db.areas.alerts.enabled, true, "setting unchanged in combat")
    t.contains(sim.output, "combat", "player told why")
    sim:LeaveCombat()

    -- The window's switch drives the same setting.
    sim:Slash("/bwk alerts")
    local nav = NS.Window.navs.alerts
    nav.switch:Click()
    t.eq(NS.db.areas.alerts.enabled, false, "window switch turns the area off")
    t.ok(not nav.switch.on, "switch shows off")
    t.eq(NS:AreaStatus("alerts"), "off", "status off")
    nav.switch:Click()
    t.ok(nav.switch.on, "switch shows on again")

    -- Settings > Areas page mirrors and moves the switches.
    NS.Window:Select("settings", "areas")
    local page = NS:GetArea("settings").pages[1]
    t.eq(#page.rows, 4, "one row per area")
    local row = page.rows[3]
    t.eq(row.area.key, "marking", "rows in tab order")
    row.switch:Click()
    t.eq(NS.db.areas.marking.enabled, false, "row switch turns marking off")
    t.ok(not row.switch.on, "row switch repainted")
    row.switch:Click()

    -- Saved off state survives a reload: the area doesn't start at login.
    local s2 = t.fresh(function(s)
        s.env.BulwarkDB = { areas = { audit = { enabled = false } } }
    end)
    t.eq(s2.env.Bulwark:AreaStatus("audit"), "off", "saved off state kept")
    t.ok(not s2.env.Bulwark:IsAreaRunning("audit"), "off area not started at login")
    t.ok(s2.env.Bulwark:IsAreaRunning("alerts"), "other areas still start")

    -- Old standalone addon still loaded: the area waits, says so once, and its tab shows the notice.
    local s3 = t.fresh(function(s)
        s.env.C_AddOns.IsAddOnLoaded = function(name) return name == "Bulwark" or name == "TankMarkForever" end
    end)
    local NS3 = s3.env.Bulwark
    t.eq(NS3:AreaStatus("marking"), "blocked", "marking waits for TankMarkForever")
    t.ok(not NS3:IsAreaRunning("marking"), "blocked area not started")
    t.ok(NS3:IsAreaRunning("alerts"), "unblocked areas start")
    t.contains(s3.output, "TankMarkForever", "login message names the old addon")
    NS3:SetAreaEnabled("marking", false)
    NS3:SetAreaEnabled("marking", true)
    t.ok(not NS3:IsAreaRunning("marking"), "switching a waiting area off and on doesn't start it")
    t.eq(NS3:AreaStatus("marking"), "blocked", "still waiting after the switch")
    NS3.Window:Open("marking")
    t.ok(NS3.Window:GetFrame() and NS3.Window:IsShown(), "window opens")
    s3:Slash("/bwk status")
    t.contains(s3.output, "Waiting for TankMarkForever", "/bwk status explains the wait")
end
