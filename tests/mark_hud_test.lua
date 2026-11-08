-- HUD: per-mark on/off (saved), title bar collapses (saved), drag saves the position; old setups and mob types migrate.
local H = require("mark_helpers")

return function(_, t)
    -- Migration: a setup and mob types saved before the Tank/CC split (e.g. imported from an old TankMarkForever).
    local old = t.fresh(function(s)
        H.install(s)
        s.env.BulwarkCharDB = { marking = { setup = { rows = {
            { icon = 8, role = "KILL" }, { icon = 7, role = "OFF" }, { icon = 6, role = "CC", player = "Lumen Brightwater" },
            { icon = 5, role = "KILL" }, { icon = 4, role = "KILL" }, { icon = 3, role = "KILL" },
            { icon = 2, role = "KILL" }, { icon = 1, role = "KILL" },
        } } } }
        s.env.BulwarkDB = { marking = { mobs = { ["Ragefire Chasm"] = {
            names = { ["Taragaman"] = { type = "KILL", prio = 1 } },
            sigs = { ["elite|MANA|126239"] = { type = "CC", prio = 9 }, ["elite|RAGE|126512"] = { type = "IGNORE" } },
        } } } }
    end)
    local rows = old.env.BulwarkCharDB.marking.setup.rows
    t.eq(rows[1].role, "TANK", "Kill becomes Tank")
    t.eq(rows[2].role, "TANK", "Off becomes Tank ...")
    t.eq(rows[2].off, true, "... switched off")
    t.eq(rows[3].role, "CC", "CC stays")
    t.eq(table.concat(old.env.Bulwark.Marking.Team:GetLadder(), ","), "8,5,4,3,2,1", "off and CC rows leave the ladder")
    local rfc = old.env.BulwarkDB.marking.mobs["Ragefire Chasm"]
    t.eq(rfc.names["Taragaman"].type, "TANK", "mob type Kill becomes Tank")
    t.eq(rfc.sigs["elite|MANA|126239"].type, "CC", "CC mob stays CC")
    t.eq(rfc.sigs["elite|RAGE|126512"].type, "IGNORE", "Ignore stays")

    -- Fresh install with a pack in view.
    local sim = t.fresh(function(s)
        H.install(s)
        H.pack(s)
    end)
    local env = sim.env
    local MK = env.Bulwark.Marking
    env.Bulwark.Marking.Plates.Changed()
    sim:Advance(1)
    local hud = env.Bulwark_MarkHUD
    t.ok(hud and hud:IsShown(), "HUD shown after login")
    local row1 = hud.rows[1]
    t.ok(row1:IsShown(), "first HUD row shown")
    t.ok((row1.text:GetText() or ""):find("Ragefire Shaman", 1, true), "row shows the mob the plan puts skull on")
    t.ok(not hud.allOn:IsShown(), "no All on button while every mark is on")

    -- Left-click switches skull off: plan, keys and announcement skip it.
    row1:Click("LeftButton")
    sim:Advance(1)
    rows = env.BulwarkCharDB.marking.setup.rows
    t.eq(rows[1].off, true, "skull switched off (saved in the setup)")
    t.ok((row1.text:GetText() or ""):find("(off)", 1, true), "row reads off")
    t.ok((hud.title.text:GetText() or ""):find("1 off", 1, true), "title counts off marks")
    t.ok(hud.allOn:IsShown(), "All on button appears")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 7, "the caster now gets cross")
    for i = 1, 8 do
        t.ok(env.BWK_CycleButton:GetAttribute("cyc" .. i) ~= 8, "cycle key never hands out skull")
    end
    t.ok(not MK.Team:BuildAnnouncement()[1]:find("{rt8}"), "skull not announced")

    -- Right-click opens the Bulwark window on Marking > Team.
    row1:Click("RightButton")
    local NS = env.Bulwark
    t.ok(NS.Window:IsShown(), "right-click opens the window")
    local area, pageKey = NS.Window:GetActive()
    t.eq(area .. "/" .. pageKey, "marking/team", "on the Team page")
    sim:Slash("/bwk")

    -- All on.
    hud.allOn:Click()
    sim:Advance(1)
    t.eq(rows[1].off, nil, "All on clears every off")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 8, "skull planned again")

    -- In combat: the toggle is saved at once, the plan follows when combat ends (no blocked secure writes).
    sim:EnterCombat()
    hud.rows[2]:Click("LeftButton")
    t.eq(rows[2].off, true, "cross switched off in combat")
    sim:LeaveCombat()
    sim:Fire("PLAYER_REGEN_ENABLED")
    sim:Advance(1)
    t.eq(env.BWK_Mark2:GetAttribute("marker"), 6, "after combat the plan skips cross")
    MK.Team:AllOn()

    -- Title bar: click collapses and expands; the state is saved.
    local title = hud.title
    title:Click()
    t.eq(env.BulwarkDB.marking.hud.collapsed, true, "collapsed (saved)")
    t.ok(not row1:IsShown(), "rows hidden while collapsed")
    title:Click()
    t.eq(env.BulwarkDB.marking.hud.collapsed, false, "expanded again")
    t.ok(row1:IsShown(), "rows back")

    -- Drag: the top-left corner is saved; the mouse-up that ends the drag doesn't collapse.
    rawset(hud, "GetLeft", function() return 300 end)
    rawset(hud, "GetTop", function() return 700 end)
    title:GetScript("OnDragStart")(title)
    title:GetScript("OnDragStop")(title)
    title:Click()
    t.eq(env.BulwarkDB.marking.hud.collapsed, false, "drag release doesn't collapse")
    local p = env.BulwarkDB.marking.hud.point
    t.ok(p and p.x == 300 and p.y == 700, "position saved")

    -- Next session: position and collapsed state come back.
    local again = t.fresh(function(s)
        H.install(s)
        s.env.BulwarkDB = { marking = { hud = { collapsed = true, point = { x = 300, y = 700 } } } }
    end)
    local hud2 = again.env.Bulwark_MarkHUD
    local point, _, relPoint, x, y = hud2:GetPoint()
    t.eq(string.format("%s %s %s %s", point, relPoint, x, y), "TOPLEFT BOTTOMLEFT 300 700", "position restored")
    t.ok(not hud2.rows[1]:IsShown(), "collapsed state restored")

    -- Module handlers run in pcall and only print their errors: fail on any.
    for _, s in ipairs({ old, sim, again }) do
        for _, line in ipairs(s.output) do
            t.ok(not line:find("Error in"), "no handler error: " .. line)
        end
    end
end
