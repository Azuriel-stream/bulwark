-- Step 4: who wears which icon. Our marks (SetRaidTarget hook) and marks learned from the %t echo (anyone's) are
-- merged, newest first. A learned mark survives later mark changes while still plausible (icon in use, plate shows an
-- icon); it frees its icon once that mob is seen dead (group case: corpse out of range); the plan report names it.
-- Another player's mark is modelled by setting units[x].raidTarget directly (it never passes our hook).
local H = require("mark_helpers")

local function setup(s)
    H.install(s)
    H.pack(s)
    s.env.RemoveRaidTargets = function() for _, x in pairs(s.units) do x.raidTarget = nil end end
end

return function(_, t)
    local sim = t.fresh(setup)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local Learn, Team, Plates, Planner = MK.Learn, MK.Team, MK.Plates, MK.Planner
    sim.restricted = true   -- dungeon: names secret
    for i = 1, 3 do sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    sim:Advance(1)
    local rec1, rec2 = Plates.records.nameplate1, Plates.records.nameplate2

    local function Learned(token, echo)
        sim.units.target = sim.units[token]
        sim:Fire("PLAYER_TARGET_CHANGED")
        sim:Advance(1)
        local n = tonumber(sim.chat[#sim.chat].msg:match("^BWK~(%d+)~"))
        sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~" .. n .. "~" .. echo, "Tankard Stoneforge")
        sim.units.target = nil
        sim:Advance(1)
    end

    -- Someone else's skull on the shaman, learned; then our key puts cross on the trogg.
    Learned("nameplate1", "Ragefire Trogg")
    sim.units.nameplate2.raidTarget = 8
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    Learned("nameplate2", "{rt8}Ragefire Shaman")
    env.SetRaidTarget("nameplate1", 7)
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    t.eq(Team:BuildAnnouncement()[1], "[Bulwark] Kill order: {rt8} Ragefire Shaman > {rt7} Ragefire Trogg",
        "someone else's skull is still named after our own marking")
    local wearer, kind = Learn.Wearer(8)
    t.ok(wearer == rec2 and kind == "learned", "skull: learned wearer")
    wearer, kind = Learn.Wearer(7)
    t.ok(wearer == rec1 and kind == "ours", "cross: ours")

    -- The plan report names the learned wearer instead of "not ours".
    Plates.Changed()
    sim:Advance(1)
    local before = #sim.output
    Planner:Report()
    local found = false
    for i = before + 1, #sim.output do
        if sim.output[i]:find("on Ragefire Shaman (seen when you targeted it)", 1, true) then found = true end
    end
    t.ok(found, "plan report: skull is on Ragefire Shaman")

    -- Group: the shaman dies and its corpse goes out of range, the client still lists skull: free to reuse.
    t.ok(Planner.plan.reserved[8], "living skull mob: skull reserved")
    sim:EnterCombat()
    sim.units.nameplate2.dead = true
    sim:Fire("UNIT_HEALTH", "nameplate2")
    sim:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    sim.units.ghost = { raidTarget = 8 }   -- the client keeps skull "taken" on a corpse it no longer knows
    sim.units.nameplate2 = nil
    sim:Advance(1)
    sim:LeaveCombat()
    sim:Advance(1)
    Plates.Changed()
    sim:Advance(1)
    t.ok(not Planner.plan.reserved[8], "learned skull on a dead mob: not reserved")
    t.ok(Planner.plan.onCorpses[8], "reported as on a corpse")
    t.eq(Learn.MobsByIcon()[8], nil, "a dead mob isn't announced")

    -- A learned mark that no longer shows (the mob got unmarked) isn't used.
    local sim2 = t.fresh(setup)
    sim2.restricted = true
    for i = 1, 3 do sim2:Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    sim2:Advance(1)
    sim, env = sim2, sim2.env
    MK = env.Bulwark.Marking
    Learn, Plates = MK.Learn, MK.Plates
    sim.units.nameplate2.raidTarget = 8
    Learned("nameplate2", "{rt8}Ragefire Shaman")
    t.eq(Learn.MobsByIcon()[8], Plates.records.nameplate2, "learned skull used")
    sim.units.nameplate2.raidTarget = nil
    sim:Fire("RAID_TARGET_UPDATE")
    t.eq(Learn.MobsByIcon()[8], nil, "unmarked since: not used")
    -- Someone moved skull to another mob, unseen: skull is still in use, but our mob's plate shows no icon.
    sim.units.nameplate2.raidTarget = 8
    Learned("nameplate2", "{rt8}Ragefire Shaman")
    sim.units.nameplate2.raidTarget, sim.units.nameplate3.raidTarget = nil, 8
    sim:Fire("RAID_TARGET_UPDATE")
    t.eq(Learn.MobsByIcon()[8], nil, "skull moved elsewhere: the old wearer isn't named")
    sim.units.nameplate3.raidTarget = nil

    -- Our key re-marks the learned mob: our newer mark wins, the old claim is void.
    sim.units.nameplate2.raidTarget = 8
    env.SetRaidTarget("nameplate2", 6)
    local byIcon = Learn.MobsByIcon()
    t.ok(byIcon[6] == Plates.records.nameplate2 and byIcon[8] == nil, "our newer mark replaces the learned one")
    t.eq(Learn.claims[8], nil, "claim for that mob dropped")

    -- Clear-all forgets learned marks too.
    sim.units.nameplate3.raidTarget = 4
    Learned("nameplate3", "{rt4}Ragefire Trogg")
    t.ok(Learn.claims[4] ~= nil, "learned")
    env.RemoveRaidTargets()
    t.eq(next(Learn.claims), nil, "clear-all empties the learned marks")
end
