-- Team setup: ladder from kill rows, CC slots from group members, owners, row order, announcement, planner use.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        s.env.UnitRace = function(u) local x = s.units[u]; if x then return x.race or "Human", x.race or "Human" end end
        s.units.party1.class = "MAGE"
    end)
    local env = sim.env
    local Team = env.Bulwark.Marking.Team
    local rows = env.BulwarkCharDB.marking.setup.rows

    t.eq(table.concat(Team:GetLadder(), ","), "8,7,6,5,4,3,2,1", "default ladder: all icons, skull first")
    t.eq(#Team:GetCCSlots(), 0, "no CC by default")
    t.eq(Team.FullName("party1"), "Lumen Brightwater", "full names carry the surname")

    -- Moon becomes Lumen's sheep.
    rows[4].role = "CC"
    rows[4].player = "Lumen Brightwater"
    t.eq(table.concat(Team:GetLadder(), ","), "8,7,6,4,3,2,1", "CC icon leaves the kill ladder")
    local slots = Team:GetCCSlots()
    t.eq(#slots, 1, "one CC slot")
    t.eq(slots[1].mark, 5, "moon")
    t.eq(slots[1].class, "MAGE", "class from the roster")

    -- Order and owners.
    Team:MoveRow(2, 1)
    t.eq(table.concat(Team:GetLadder(), ","), "8,6,7,4,3,2,1", "moving a row changes the kill order")
    Team:MoveRow(2, 1)
    t.eq(table.concat(Team:GetLadder(), ","), "8,7,6,4,3,2,1", "moved back")
    rows[1].player = "Tankard Stoneforge"
    sim.units.player.dead = true
    t.eq(Team:GetLadder()[1], 7, "skull skipped while its tank is dead")
    sim.units.player.dead = false

    -- Cycling a player walks the group, then back to none.
    Team:CyclePlayer(8)
    t.eq(rows[8].player, "Tankard Stoneforge", "first member")
    Team:CyclePlayer(8)
    t.eq(rows[8].player, "Lumen Brightwater", "second member")
    Team:CyclePlayer(8)
    t.eq(rows[8].player, nil, "back to anyone")

    -- Announcement in party chat.
    rows[3].off = true
    local lines = Team:BuildAnnouncement()
    t.eq(lines[1], "[Bulwark] Kill order: {rt8} Tankard > {rt7} > {rt4} > {rt3} > {rt2} > {rt1}", "kill line")
    t.eq(lines[2], "[Bulwark] CC: {rt5} Lumen (Polymorph)", "CC line")
    local before = #sim.chat
    sim:Slash("/bwk mark announce")
    t.eq(#sim.chat - before, 2, "two messages")
    t.ok(sim.chat[#sim.chat].channel == "PARTY", "announced to party")
    rows[4].role = "TANK"
    t.eq(#Team:BuildAnnouncement(), 1, "no CC line without CC rows")
    rows[4].role = "CC"

    -- Planner: a mob taught as CC (no class, instance: no creature type) goes to Lumen's moon.
    H.pack(sim)
    sim.units.nameplate2.ctype = nil
    for i = 1, 3 do sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    env.Bulwark.Marking.Plates.zone = "Test Zone"
    local zone = env.Bulwark.Marking:GetZoneMobs("Test Zone")
    zone.names["Ragefire Shaman"] = { type = "CC", prio = 9 }
    env.Bulwark.Marking.Plates.Changed()
    sim:Advance(1)
    local planned = {}
    for _, e in ipairs(env.Bulwark.Marking.Planner.plan.entries) do planned[e.rec.token] = e.icon end
    t.eq(planned.nameplate2, 5, "taught CC mob gets the CC icon")
    t.eq(planned.nameplate1, 8, "kill ladder for the rest (lower-level trogg first)")
end
