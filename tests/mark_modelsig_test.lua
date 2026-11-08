-- Model signatures: the model file ID keeps mob types apart inside instances (names hidden), level-free, so one entry
-- covers a mob type at every level; model-less entries still apply as a fallback; old "level|...|model" keys migrate.
local H = require("mark_helpers")

local TROGG, WORM = 126239, 126512

local function setup(blocked, savedDB)
    return function(s)
        H.install(s)
        s.modelsBlocked = blocked
        if savedDB then s.env.BulwarkDB = { marking = savedDB } end
        local realName = s.env.UnitName
        s.env.UnitName = function(u)   -- names hidden, as inside an instance
            if u:find("^nameplate") then return nil end
            return realName(u)
        end
        s.units.target = nil
        s.units.nameplate1 = { guid = "Creature-0-1-0-1-11318-1", friendly = false, level = 14, tier = "elite",
                               power = "RAGE", model = TROGG }   -- Ragefire Trogg
        s.units.nameplate2 = { guid = "Creature-0-1-0-1-11320-2", friendly = false, level = 14, tier = "elite",
                               power = "RAGE", model = WORM }    -- Earthborer
        s.units.nameplate3 = { guid = "Creature-0-1-0-1-11318-3", friendly = false, level = 15, tier = "elite",
                               power = "RAGE", model = TROGG }   -- another trogg, higher level
    end
end

return function(_, t)
    local sim = t.fresh(setup(false))
    local MK = sim.env.Bulwark.Marking
    local Plates, MobDB = MK.Plates, MK.MobDB

    t.eq(Plates.records.nameplate1.sig, "elite|RAGE|126239", "model signature is level-free")
    t.eq(Plates.records.nameplate3.sig, "elite|RAGE|126239", "same mob type at another level: same signature")
    t.eq(Plates.records.nameplate2.sig, "elite|RAGE|126512", "worm differs")
    t.eq(Plates.records.nameplate2.sigBase, "14|elite|RAGE", "level-based fallback kept")
    t.eq(MobDB.DescribeSig(Plates.records.nameplate2.sig), "elite worm melee", "label names the model, no level")
    t.eq(MobDB.DescribeSig("14|elite|MANA"), "lvl 14 elite caster", "model-less label keeps the level")

    -- Learning the worm doesn't touch the trogg (the user's collision); one trogg entry covers levels 14 and 15.
    sim.units.mouseover = sim.units.nameplate2
    sim:Slash("/bwk mark learn 1")
    sim.units.mouseover = sim.units.nameplate1
    sim:Slash("/bwk mark learn 9")
    local zone = MK.db.mobs[Plates.zone]
    t.ok(zone.sigs["elite|RAGE|126512"], "worm learned")
    local trogg = zone.sigs["elite|RAGE|126239"]
    t.eq(trogg.prio, 9, "trogg learned once")
    sim:Advance(1)
    t.eq(sim.env.BWK_Mark1:GetAttribute("unit"), "nameplate2", "the worm (prio 1) gets skull")
    t.eq(MobDB.LevelText(trogg), "14-15", "levels seen are tracked")

    -- A model-less entry (learned before) covers what has no model entry; the model entry wins.
    zone.sigs["14|elite|RAGE"] = { type = "IGNORE" }
    zone.sigs["elite|RAGE|126239"] = nil
    Plates.Changed()
    sim:Advance(1)
    local planned = {}
    for _, e in ipairs(MK.Planner.plan.entries) do planned[e.rec.token] = e.icon end
    t.eq(planned.nameplate1, nil, "lvl 14 trogg falls back to the level entry (ignored)")
    t.eq(planned.nameplate2, 8, "worm keeps its own entry")
    t.ok(planned.nameplate3 ~= nil, "lvl 15 trogg isn't covered by the lvl 14 fallback")

    -- Loophole closed: no model, level-based signatures, nothing breaks.
    local sim2 = t.fresh(setup(true))
    local recs = sim2.env.Bulwark.Marking.Plates.records
    t.eq(recs.nameplate1.sig, "14|elite|RAGE", "no model: level-based signature")
    t.eq(recs.nameplate1.model, nil, "no model recorded")

    -- Migration of step-1 keys: levels dropped, duplicates merged (first by key kept), levels remembered.
    local saved = { mobs = { ["Test Zone"] = { names = {}, sigs = {
        ["13|elite|RAGE|126239"] = { type = "TANK", prio = 3 },
        ["14|elite|RAGE|126239"] = { type = "TANK", prio = 7 },
        ["14|elite|RAGE|126512"] = { type = "TANK", prio = 1 },
        ["14|elite|MANA"] = { type = "TANK", prio = 2 },
    } } } }
    local sim3 = t.fresh(setup(false, saved))
    local sigs = sim3.env.BulwarkDB.marking.mobs["Test Zone"].sigs
    t.eq(sigs["elite|RAGE|126239"].prio, 3, "trogg entries merged, the first kept")
    t.eq(sim3.env.Bulwark.Marking.MobDB.LevelText(sigs["elite|RAGE|126239"]), "13-15", "merged levels 13+14, plus the live lvl 15 trogg")
    t.eq(sigs["14|elite|RAGE|126239"], nil, "old key gone")
    t.ok(sigs["elite|RAGE|126512"], "worm migrated")
    t.ok(sigs["14|elite|MANA"], "model-less entry untouched")
    sim3:Advance(6)
    local said = false
    for _, line in ipairs(sim3.output) do if line:find("merged") then said = true end end
    t.ok(said, "the merge is announced")
end
