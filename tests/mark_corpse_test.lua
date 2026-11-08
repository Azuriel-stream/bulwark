-- A mark left on a corpse the client no longer knows (out of range, despawned): the dead-mob flag can't free it,
-- so the client keeps the icon "taken" [in-game 2026-10-16]. Icons this client put on a mob MK saw die are free;
-- other marks the client reports stay reserved.
local H = require("mark_helpers")

local function setup(s)
    H.install(s)
    H.pack(s)
    -- Blizzard's secure raidtarget action calls these globals (SecureTemplates.lua); the clear key's clear-all too.
    s.env.RemoveRaidTargets = function() for _, x in pairs(s.units) do x.raidTarget = nil end end
end

-- The skull mob dies in combat; its plate goes, the corpse despawns, and the client still lists skull on it.
local function KillAndDespawn(sim, unit)
    sim:EnterCombat()
    sim.units[unit].dead = true
    sim:Fire("UNIT_HEALTH", unit)
    sim:Fire("NAME_PLATE_UNIT_REMOVED", unit)
    sim.units.ghost = { raidTarget = sim.units[unit].raidTarget }   -- not known as dead any more
    sim.units[unit] = nil
    sim:Advance(1)
    sim:LeaveCombat()
    sim:Advance(1)
end

return function(_, t)
    -- Skull put on by this client (MK's key): freed after the kill, planned on the next mob.
    local sim = t.fresh(setup)
    local env = sim.env
    env.SetRaidTarget("nameplate1", 8)
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    t.ok(env.Bulwark.Marking.Planner.plan.reserved[8], "living skull mob: skull reserved")
    KillAndDespawn(sim, "nameplate1")
    local plan = env.Bulwark.Marking.Planner.plan
    t.ok(not plan.reserved[8], "skull on a despawned corpse we marked isn't reserved")
    t.ok(plan.onCorpses[8], "reported as on a corpse")
    t.eq(env.BWK_Mark1:GetAttribute("marker"), 8, "skull planned again")

    -- The plate goes before UNIT_HEALTH reports the death: the removal still notices the corpse.
    local sim2 = t.fresh(setup)
    sim2.env.SetRaidTarget("nameplate1", 8)
    sim2:Advance(1)
    sim2.units.nameplate1.dead = true
    sim2:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    sim2.units.ghost, sim2.units.nameplate1 = { raidTarget = 8 }, nil
    sim2:Advance(1)
    t.ok(not sim2.env.Bulwark.Marking.Planner.plan.reserved[8], "death seen at plate removal frees skull")

    -- A mark this client didn't set (another player's, on a mob out of sight) stays reserved.
    local sim3 = t.fresh(function(s) setup(s); s.units.ghost = { raidTarget = 8 } end)
    sim3:Advance(1)
    t.ok(sim3.env.Bulwark.Marking.Planner.plan.reserved[8], "unknown mark stays reserved")
    sim3:Slash("/bwk mark plan")   -- prints why skull is kept

    -- Clear-all forgets what we placed; a later skull on a living mob is reserved again.
    local sim4 = t.fresh(setup)
    sim4.env.SetRaidTarget("nameplate1", 8)
    KillAndDespawn(sim4, "nameplate1")
    sim4.env.RemoveRaidTargets()
    t.eq(next(sim4.env.Bulwark.Marking.Planner.placed), nil, "clear-all empties the list")
    sim4.units.ghost = { raidTarget = 8 }
    sim4:Fire("RAID_TARGET_UPDATE")
    sim4:Advance(1)
    t.ok(sim4.env.Bulwark.Marking.Planner.plan.reserved[8], "after clear-all, an unknown skull is reserved again")

    -- Removing one mob's mark by hand (SetRaidTarget(unit, 0)) forgets it.
    local sim5 = t.fresh(setup)
    sim5.env.SetRaidTarget("nameplate2", 7)
    t.ok(sim5.env.Bulwark.Marking.Planner.placed[7], "cross remembered")
    sim5.env.SetRaidTarget("nameplate2", 0)
    t.eq(sim5.env.Bulwark.Marking.Planner.placed[7], nil, "cross forgotten when removed")

    -- Solo: only this client marks. A taken icon no mob in view wears (from before a /reload) is free.
    local solo = t.fresh(function(s) setup(s); s.group = "none"; s.units.ghost = { raidTarget = 8 } end)
    solo:Advance(1)
    local sp = solo.env.Bulwark.Marking.Planner.plan
    t.ok(not sp.reserved[8], "solo: unknown skull out of view is free")
    t.ok(sp.stale[8], "reported as not on any mob in view")
    t.eq(solo.env.BWK_Mark1:GetAttribute("marker"), 8, "solo: skull planned again")
    solo:Slash("/bwk mark plan")

    -- Solo, but a mob in view wears an icon we didn't set (its icon is secret): unknown icons stay kept.
    local solo2 = t.fresh(function(s)
        setup(s); s.group = "none"; s.units.ghost = { raidTarget = 8 }; s.units.nameplate2.raidTarget = 7
    end)
    solo2:Advance(1)
    t.ok(solo2.env.Bulwark.Marking.Planner.plan.reserved[8], "solo: kept while a visible marked mob is unaccounted for")

    -- Solo: our skull on a living mob in view stays kept.
    local solo3 = t.fresh(function(s) setup(s); s.group = "none" end)
    solo3.env.SetRaidTarget("nameplate1", 8)
    solo3:Fire("RAID_TARGET_UPDATE")
    solo3:Advance(1)
    t.ok(solo3.env.Bulwark.Marking.Planner.plan.reserved[8], "solo: our skull on a living mob in view is kept")
end
