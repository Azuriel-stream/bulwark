-- Plates -> plan -> secure attributes; Shift-hover selection; learning; pull lock; combat freeze.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        H.pack(s)
    end)
    local env = sim.env
    env.Bulwark.Marking.Plates.Changed()
    sim:Advance(1)

    local pack = env.BWK_PackButton
    t.eq(pack:GetAttribute("macrotext"), "/click BWK_Mark1\n/click BWK_Mark2\n/click BWK_Mark3", "pack macro clicks 3 mark buttons")
    t.eq(env.BWK_Mark1:GetAttribute("unit"), "nameplate2", "first entry: the caster")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 8, "caster gets skull")
    t.eq(env.BWK_Mark1:GetAttribute("action"), "set-unmarked", "never overwrite an existing mark")
    t.eq(env.BWK_Mark4:GetAttribute("action"), "none", "unused mark buttons do nothing")
    local skull = env.BWK_SkullButton
    t.eq(skull:GetAttribute("action"), "set", "skull key moves skull (no toggle-off)")
    t.eq(skull:GetAttribute("marker"), 8, "skull key sets skull")
    local cycle = env.BWK_CycleButton
    t.eq(cycle:GetAttribute("cyc1"), 5, "cycle key starts after the plan's icons (8,7,6)")
    t.eq(cycle:GetAttribute("cycn"), 5, "5 cycle icons left")

    -- Shift-hover selects one mob: the plan shrinks to it.
    sim.shift = true
    sim.units.mouseover = sim.units.nameplate3
    sim:Fire("UPDATE_MOUSEOVER_UNIT")
    sim:Advance(1)
    t.eq(pack:GetAttribute("macrotext"), "/click BWK_Mark1", "only the selected mob is planned")
    t.eq(env.BWK_Mark1:GetAttribute("unit"), "nameplate3", "selected mob")
    -- Hover a second trogg (lower level): the first hovered keeps skull, the new one gets cross.
    sim.units.mouseover = sim.units.nameplate1
    sim:Fire("UPDATE_MOUSEOVER_UNIT")
    sim:Advance(1)
    t.eq(env.BWK_Mark1:GetAttribute("unit"), "nameplate3", "first hovered trogg keeps skull")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 8, "still skull")
    t.eq(env.BWK_Mark2:GetAttribute("unit"), "nameplate1", "second hovered trogg next")
    t.eq(env.BWK_Mark2:GetAttribute("marker"), 7, "gets cross")
    env.Bulwark.Marking.Plates:ClearSelection(true)
    sim.shift = false
    sim:Advance(1)

    -- Learn: hovering a trogg + /tmf learn 1 -> trogg (by name, open world) gets skull.
    sim.units.mouseover = sim.units.nameplate1
    sim:Slash("/bwk mark learn 1")
    sim:Advance(1)
    t.ok(env.BulwarkDB.marking.mobs["Test Zone"].names["Ragefire Trogg"], "learned by name in the open world")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 8, "skull first")
    local first = env.BWK_Mark1:GetAttribute("unit")
    t.ok(first == "nameplate1" or first == "nameplate3", "a trogg now gets skull")

    -- A worn icon is reserved: mark nameplate1 with skull -> it leaves the plan, skull isn't reused.
    sim.units.mouseover = nil
    sim.units.nameplate1.raidTarget = 8
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    for k = 1, 3 do
        local b = env["BWK_Mark" .. k]
        if b:GetAttribute("action") ~= "none" then
            t.ok(b:GetAttribute("unit") ~= "nameplate1", "marked mob left the plan")
            t.ok(b:GetAttribute("marker") ~= 8, "worn skull not planned again")
        end
    end

    t.ok(env.Bulwark.Marking.Planner.plan.reserved[8], "living skull mob: skull reserved")

    -- The skull mob dies (in combat): after combat the corpse's skull is free again and planned on the next mob.
    sim:EnterCombat()
    sim.units.nameplate1.dead = true
    sim:Fire("UNIT_HEALTH", "nameplate1")
    sim:Advance(1)
    sim:LeaveCombat()
    sim:Advance(1)
    local plan = env.Bulwark.Marking.Planner.plan
    t.ok(not plan.reserved[8], "skull on a corpse isn't reserved")
    t.ok(plan.onCorpses[8], "skull reported as on a corpse")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 8, "skull planned again after the kill")
    t.ok(env.BWK_Mark1:GetAttribute("unit") ~= "nameplate1", "not on the corpse")
    sim:Slash("/bwk mark plan")

    -- Debug trace: key presses are logged when on.
    sim:Slash("/bwk debug on")
    env.BWK_SkullButton:Click("LeftButton", true)
    env.BWK_PackButton:Click("LeftButton", true)
    t.ok(#env.BulwarkDB.debugLog >= 1, "debug log records key presses")

    -- Combat: plan frozen, no protected calls (the runner fails on any blocked SetAttribute).
    local macroBefore = pack:GetAttribute("macrotext")
    sim:EnterCombat()
    sim.units.nameplate5 = { name = "Ragefire Trogg", guid = "Creature-0-1-0-1-11318-0000000005", friendly = false,
                             level = 15, tier = "elite", power = "RAGE" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    sim:Advance(1)
    t.eq(pack:GetAttribute("macrotext"), macroBefore, "plan frozen in combat")
end
