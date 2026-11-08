-- Recorder: inside instances, new mob types seen out of combat become Kill entries with the rules' priority.
-- Never overwrites, waits for the model, skips critters, pauses in combat, off in the open world or when disabled.
local H = require("mark_helpers")

local TROGG, WORM = 126239, 126512

local function setup(opts)
    return function(s)
        H.install(s)
        s.modelsBlocked = opts.blocked
        s.env.IsInInstance = function() return not opts.openWorld, opts.openWorld and "none" or "party" end
        s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389, 5, nil, false end
        local realName = s.env.UnitName
        s.env.UnitName = function(u)   -- names hidden inside instances
            if u:find("^nameplate") then return nil end
            return realName(u)
        end
        s.units.target = nil
        if opts.saved then s.env.BulwarkDB = { marking = opts.saved } end
        s.units.nameplate1 = { guid = "Creature-0-1-0-1-1-1", friendly = false, level = 14, tier = "elite",
                               power = "MANA", model = TROGG }   -- Ragefire Shaman
        s.units.nameplate2 = { guid = "Creature-0-1-0-1-1-2", friendly = false, level = 13, tier = "elite",
                               power = "RAGE", model = TROGG }   -- Ragefire Trogg
        s.units.nameplate3 = { guid = "Creature-0-1-0-1-1-3", friendly = false, level = 16, tier = "elite",
                               power = "RAGE", model = TROGG }   -- Oggleflint
        s.units.nameplate4 = { guid = "Creature-0-1-0-1-1-4", friendly = false, level = 15, tier = "elite",
                               power = "RAGE", model = TROGG }   -- another trogg: same entry
        s.units.nameplate5 = { guid = "Creature-0-1-0-1-1-5", friendly = false, level = 1, tier = "normal",
                               power = "RAGE", model = 999, ctype = "Critter" }
    end
end

local function count(list, pattern)
    local n = 0
    for _, line in ipairs(list) do if line:find(pattern, 1, true) then n = n + 1 end end
    return n
end

return function(_, t)
    local saved = { mobs = { ["Test Zone"] = { names = {}, sigs = { ["elite|RAGE|126512"] = { type = "IGNORE" } } } } }
    local sim = t.fresh(setup({ saved = saved }))
    local MK = sim.env.Bulwark.Marking
    sim:Advance(2)
    local sigs = MK.db.mobs["Test Zone"].sigs
    t.eq(sigs["elite|MANA|126239"] and sigs["elite|MANA|126239"].prio, 2, "shaman recorded, caster prio")
    t.eq(sigs["elite|RAGE|126239"] and sigs["elite|RAGE|126239"].prio, 4, "trogg recorded, melee prio")
    t.eq(sigs["boss|RAGE|126239"] and sigs["boss|RAGE|126239"].prio, 1, "boss recorded on its own")
    t.eq(MK.MobDB.LevelText(sigs["elite|RAGE|126239"]), "13-15", "both troggs' levels noted, Oggleflint's not")
    local n = 0
    for _ in pairs(sigs) do n = n + 1 end
    t.eq(n, 4, "critter skipped, no duplicates (3 recorded + the saved worm)")
    t.eq(count(sim.output, "Recorded: Ragefire Shaman (prio 2)"), 1, "one chat line per new mob, named from the data")
    t.eq(count(sim.output, "Recorded: Oggleflint (prio 1)"), 1, "boss line")
    t.eq(MK.db.mobs["Test Zone"].instanceID, 389, "zone remembers its instance")

    -- Existing entries aren't touched; a second pass records nothing.
    sigs["elite|RAGE|126239"].prio = 9
    t.eq(MK.MobDB:RecordVisible(), 0, "nothing new")
    t.eq(sigs["elite|RAGE|126239"].prio, 9, "the player's change kept")

    -- A new mob type appearing in combat waits for combat to end.
    sim:EnterCombat()
    sim.units.nameplate6 = { guid = "Creature-0-1-0-1-1-6", friendly = false, level = 14, tier = "elite",
                             power = "RAGE", model = WORM + 1 }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
    sim:Advance(2)
    t.eq(sigs["elite|RAGE|126513"], nil, "not recorded in combat")
    sim:LeaveCombat()
    sim:Advance(2)
    t.ok(sigs["elite|RAGE|126513"], "recorded when combat ends")

    -- Turned off: nothing recorded (the checkbox on the Options page).
    MK:Set("record", false)
    sim.units.nameplate7 = { guid = "Creature-0-1-0-1-1-7", friendly = false, level = 14, tier = "elite",
                             power = "MANA", model = WORM + 2 }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
    sim:Advance(2)
    t.eq(sigs["elite|MANA|126514"], nil, "recorder off")
    local record = H.page(sim, "options").boxes.record
    t.ok(not record:GetChecked(), "checkbox shows off")
    record:Click()
    t.ok(MK:Get("record"), "checkbox turns it on")
    t.ok(sigs["elite|MANA|126514"], "turning it on records what's visible")

    -- Open world: never.
    local sim2 = t.fresh(setup({ openWorld = true }))
    sim2:Advance(2)
    t.eq(sim2.env.Bulwark.Marking.db.mobs["Test Zone"], nil, "open world: nothing recorded")

    -- No model (loophole closed): nothing recorded (no level-based entries).
    local sim3 = t.fresh(setup({ blocked = true }))
    sim3:Advance(3)
    t.eq(sim3.env.Bulwark.Marking.db.mobs["Test Zone"], nil, "no model: nothing recorded")
end
