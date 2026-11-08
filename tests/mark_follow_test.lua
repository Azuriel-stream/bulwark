-- Follow marks: a group member wears a Follow row's mark; the pack key puts it on first, the clear key clears all
-- and puts it back; never planned on a mob; not on skull; announced; HUD lock.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        H.pack(s)
    end)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local Team = MK.Team
    local rows = env.BulwarkCharDB.marking.setup.rows

    -- Role cycle: Tank -> CC -> Follow -> Tank, but skull skips Follow (the next-skull key would take it).
    Team:CycleRole(1)
    Team:CycleRole(1)
    t.eq(rows[1].role, "TANK", "skull can't be a Follow mark")
    Team:CycleRole(8)
    Team:CycleRole(8)
    t.eq(rows[8].role, "FOLLOW", "star becomes a Follow mark")
    t.eq(#Team:GetFollows(), 0, "no follow mark without a player")
    rows[8].player = "Tankard Stoneforge"
    t.eq(Team.Migrate(rows), nil)
    t.eq(rows[8].role, "FOLLOW", "migration keeps Follow rows")

    -- A mob taught to always wear star must not take it from the tank.
    MK.Plates.zone = "Test Zone"
    MK:GetZoneMobs("Test Zone").names["Ragefire Trogg"] = { type = "TANK", prio = 5, icon = 1 }
    MK.Plates.Changed()
    sim:Advance(1)

    local follow = env.BWK_Follow1
    t.eq(follow:GetAttribute("unit"), "player", "you wear your own follow mark (token never changes)")
    t.eq(follow:GetAttribute("marker"), 1, "star")
    t.eq(follow:GetAttribute("action"), "set-unmarked", "never toggles a worn mark off")
    t.eq(follow:GetAttribute("useOnKeyDown"), false, "acts on /click (down=false)")
    t.eq(env.BWK_Follow2:GetAttribute("action"), "none", "unused follow buttons do nothing")
    local pack = env.BWK_PackButton:GetAttribute("macrotext")
    t.ok(pack:find("^/click BWK_Follow1\n/click BWK_Mark1"), "pack key puts the follow mark on first: " .. pack)
    t.eq(env.BWK_ClearButton:GetAttribute("type"), "macro", "clear key is a macro")
    t.eq(env.BWK_ClearButton:GetAttribute("macrotext"), "/click BWK_ClearAll\n/click BWK_Follow1",
        "clear key: clear all, then the follow mark")
    t.eq(env.BWK_ClearAll:GetAttribute("action"), "clear-all", "clear-all button")
    for _, e in ipairs(MK.Planner.plan.entries) do
        t.ok(e.icon ~= 1, "star never planned on a mob (" .. e.rec.token .. ")")
    end
    for i = 1, 8 do
        t.ok(env.BWK_CycleButton:GetAttribute("cyc" .. i) ~= 1, "cycle key never hands out star")
    end
    t.ok(not table.concat(Team:GetLadder(), ","):find("1"), "star not in the kill ladder")

    -- Another group member: their party token.
    Team:CycleRole(7)
    Team:CycleRole(7)
    rows[7].player = "Lumen Brightwater"
    MK.Plates.Changed()
    sim:Advance(1)
    -- Buttons follow the setup row order: circle (row 7) first, then star (row 8).
    t.eq(env.BWK_Follow1:GetAttribute("unit"), "party1", "a group member's follow mark")
    t.eq(env.BWK_Follow1:GetAttribute("marker"), 2, "circle")
    t.eq(env.BWK_Follow2:GetAttribute("unit"), "player", "yours next")
    t.eq(env.BWK_ClearButton:GetAttribute("macrotext"), "/click BWK_ClearAll\n/click BWK_Follow1\n/click BWK_Follow2",
        "clear key puts both back")
    local lines = Team:BuildAnnouncement()
    t.eq(lines[#lines], "[Bulwark] Follow: {rt2} Lumen, {rt1} Tankard", "follow line")

    -- HUD: a Follow section; switching it off stops the re-marking.
    local hud = env.Bulwark_MarkHUD
    t.ok(hud.headers.FOLLOW:IsShown(), "Follow header in the HUD")
    Team:ToggleOff(8)
    sim:Advance(1)
    t.eq(env.BWK_ClearButton:GetAttribute("macrotext"), "/click BWK_ClearAll\n/click BWK_Follow1",
        "only the follow mark that's on comes back")
    t.eq(env.BWK_Follow1:GetAttribute("unit"), "party1", "the remaining follow mark")
    lines = Team:BuildAnnouncement()
    t.eq(lines[#lines], "[Bulwark] Follow: {rt2} Lumen", "an off follow mark isn't announced")
    Team:AllOn()

    -- Marking switched off: the clear key only clears.
    env.Bulwark:SetAreaEnabled("marking", false)
    t.eq(env.BWK_ClearButton:GetAttribute("macrotext"), "/click BWK_ClearAll", "disabled: plain clear")
    t.eq(env.BWK_Follow1:GetAttribute("action"), "none", "disabled: no follow marks")
    env.Bulwark:SetAreaEnabled("marking", true)

    -- Lock: the title bar stops dragging; the state is saved.
    local moved = 0
    rawset(hud, "StartMoving", function() moved = moved + 1 end)
    hud.lock:Click()
    t.eq(env.BulwarkDB.marking.hud.locked, true, "locked (saved)")
    hud.title:GetScript("OnDragStart")(hud.title)
    t.eq(moved, 0, "locked: no drag")
    hud.lock:Click()
    t.eq(env.BulwarkDB.marking.hud.locked, nil, "unlocked")
    hud.title:GetScript("OnDragStart")(hud.title)
    t.eq(moved, 1, "unlocked: drags")

    for _, line in ipairs(sim.output) do
        t.ok(not line:find("Error in"), "no handler error: " .. line)
    end
end
