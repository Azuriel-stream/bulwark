-- Range cap: out of combat, only plates within ~30 yd are planned; the plan follows the player; a Shift-hover
-- selection overrides it; the checkbox turns it off; unknown range never excludes a mob.
local H = require("mark_helpers")

local function planned(MK)
    local by = {}
    for _, e in ipairs(MK.Planner.plan.entries) do by[e.rec.token] = e.icon end
    return by
end

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        H.pack(s)
        s.units.nameplate3.far = true   -- the next pack, out of reach
    end)
    local MK = sim.env.Bulwark.Marking
    sim:Advance(1)
    local by = planned(MK)
    t.ok(by.nameplate1 and by.nameplate2, "near mobs planned")
    t.eq(by.nameplate3, nil, "far mob not planned")
    sim:Slash("/bwk mark plan")
    local said = false
    for _, line in ipairs(sim.output) do if line:find("too far", 1, true) then said = true end end
    t.ok(said, "/bwk mark plan says it's too far")

    -- Walking up: the ticker re-checks range out of combat and the plan follows.
    sim.units.nameplate3.far = false
    sim.units.nameplate1.far = true
    sim:Advance(1)
    by = planned(MK)
    t.ok(by.nameplate3, "approached mob planned")
    t.eq(by.nameplate1, nil, "mob left behind dropped")

    -- A Shift-hover selection overrides the cap.
    MK.Plates.selected.nameplate1 = true
    MK.Plates.Changed()
    sim:Advance(1)
    t.ok(planned(MK).nameplate1, "selected far mob planned")
    MK.Plates:ClearSelection(true)

    -- In combat the range isn't re-checked (the plan is frozen anyway).
    sim:EnterCombat()
    sim.units.nameplate1.far = false
    sim:Advance(1)
    t.eq(MK.Plates.records.nameplate1.far, true, "no range checks in combat")
    sim:LeaveCombat()
    sim:Advance(1)
    t.eq(MK.Plates.records.nameplate1.far, false, "re-checked after combat")

    -- Line of sight: a near mob hidden behind terrain (faded plate) is left out until it comes into view.
    sim.units.nameplate1.hidden = true
    sim:Advance(1)
    t.eq(planned(MK).nameplate1, nil, "hidden mob not planned")
    sim:Slash("/bwk mark plan")
    local sight = false
    for _, line in ipairs(sim.output) do if line:find("out of sight", 1, true) then sight = true end end
    t.ok(sight, "/bwk mark plan says it's out of sight")
    MK.Plates.selected.nameplate1 = true
    MK.Plates.Changed()
    sim:Advance(1)
    t.ok(planned(MK).nameplate1, "Shift-hover still plans a hidden mob")
    MK.Plates:ClearSelection(true)
    -- CVars changed so the fade bands overlap: can't tell, never excluded.
    sim.cvars.nameplateOccludedAlphaMult = "1"
    sim:Advance(1)
    t.ok(planned(MK).nameplate1, "occlusion fade off: not excluded")
    sim.cvars.nameplateOccludedAlphaMult = "0.400000"
    sim.units.nameplate1.hidden = false
    sim:Advance(1)
    t.ok(planned(MK).nameplate1, "in view again: planned")

    -- The checkbox turns the cap off.
    sim.units.nameplate2.far = true
    sim:Advance(1)
    t.eq(planned(MK).nameplate2, nil, "far again")
    local near = H.page(sim, "options").boxes.nearOnly
    t.ok(near:GetChecked(), "checkbox on by default")
    near:Click()
    sim:Advance(1)
    t.ok(not MK:Get("nearOnly"), "turned off")
    t.ok(planned(MK).nameplate2, "far mob planned with the cap off")

    -- Range unknown (both checks nil): never excluded.
    local sim2 = t.fresh(function(s)
        H.install(s)
        H.pack(s)
        s.env.C_Item.IsItemInRange = function() return nil end
        s.env.CheckInteractDistance = function() return nil end
    end)
    sim2:Advance(1)
    t.eq(#sim2.env.Bulwark.Marking.Planner.plan.entries, 3, "unknown range: all planned")
end
