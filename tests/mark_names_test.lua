-- Step 2: real names into the mob database (MobDB:AdoptName), from the %t echo and from the damage meter.
-- Existing entries are never changed; a new name entry copies the settings of the body (signature) entry it matched.
-- Ragefire Chasm (389): one Searing Blade body (model 917116) is shared by Cultist + Warlock (mana) and Enforcer (rage).
local H = require("mark_helpers")
local RFC = 389

return function(_, t)
    local meterRows = {}
    local sim = t.fresh(function(s)
        H.install(s)
        s.zone = "Ragefire Chasm"
        s.env.IsInInstance = function() return true, "party" end
        s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, RFC, 5, nil, false end
        s.env.C_DamageMeter = {
            GetCombatSessionFromType = function()
                if s.inCombat then error("secret in combat") end
                return { combatSources = meterRows }
            end,
        }
    end)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local Learn, MobDB, Planner, Plates = MK.Learn, MK.MobDB, MK.Planner, MK.Plates
    env.Enum.DamageMeterSessionType = env.Enum.DamageMeterSessionType or { Current = 1 }
    env.Enum.DamageMeterType = env.Enum.DamageMeterType or { EnemyDamageTaken = 10 }

    -- Your tuning before step 2: the caster body is CC (moon, mage) prio 2, with a note; the Warlock has its own entry.
    local zone = MK:GetZoneMobs("Ragefire Chasm")
    local BODY = "elite|MANA|917116"
    zone.sigs[BODY] = { type = "CC", prio = 2, icon = 5, class = "MAGE", note = "casters" }
    zone.names["Searing Blade Warlock"] = { type = "TANK", prio = 9 }

    sim.units.nameplate1 = { name = "Searing Blade Cultist", friendly = false, level = 14, tier = "elite",
                             power = "MANA", model = 917116 }
    sim.units.nameplate2 = { name = "Searing Blade Warlock", friendly = false, level = 14, tier = "elite",
                             power = "MANA", model = 917116 }
    sim.restricted = true   -- dungeon: names secret
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    sim:Advance(1)
    local rec1 = Plates.records.nameplate1
    t.eq(rec1.sig, BODY, "the plate matches the caster body entry")

    local function LearnTarget(token, echoName)
        sim.units.target = sim.units[token]
        sim:Fire("PLAYER_TARGET_CHANGED")
        local n = tonumber(sim.chat[#sim.chat].msg:match("^BWK~(%d+)~"))
        sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~" .. n .. "~" .. echoName, "Tankard Stoneforge")
        sim:Advance(1)
    end

    -- Learned by targeting: a new name entry with the body's settings; the body entry stays as it was.
    LearnTarget("nameplate1", "Searing Blade Cultist")
    local cultist = zone.names["Searing Blade Cultist"]
    t.ok(cultist, "name entry added")
    t.ok(cultist.type == "CC" and cultist.prio == 2 and cultist.icon == 5 and cultist.class == "MAGE",
        "settings copied from the body entry")
    t.eq(cultist.note, nil, "the body's note isn't copied (the name says it)")
    local body = zone.sigs[BODY]
    t.ok(body and body.type == "CC" and body.prio == 2 and body.note == "casters", "body entry unchanged")
    local _, source = Planner.Knowledge(rec1, zone)
    t.eq(source, "name", "the planner now uses the name entry for that plate")
    cultist.prio = 7
    t.eq(Planner.Knowledge(rec1, zone).prio, 7, "editing the name entry affects only that mob")
    t.eq(body.prio, 2, "the body entry keeps its own value")

    -- An existing name entry is never overwritten.
    LearnTarget("nameplate2", "Searing Blade Warlock")
    t.ok(zone.names["Searing Blade Warlock"].prio == 9 and zone.names["Searing Blade Warlock"].type == "TANK",
        "existing name entry untouched")

    -- No body entry and recording off: nothing added.
    env.BulwarkDB.marking.record = false
    zone.sigs["elite|RAGE|126512"] = nil
    sim.units.nameplate3 = { name = "Earthborer", friendly = false, level = 14, tier = "elite", power = "RAGE", model = 126512 }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    sim:Advance(1)
    LearnTarget("nameplate3", "Earthborer")
    t.eq(zone.names["Earthborer"], nil, "recording off and no body entry: not added")
    env.BulwarkDB.marking.record = true

    -- Damage meter after a pull: names matched to the data give the body; the boss gets the boss priority.
    local sigs, prio = Learn.FromMeterRow(RFC, "Taragaman the Hungerer", "elite")
    t.eq(table.concat(sigs, ","), "boss|RAGE|123870", "data: boss body")
    t.eq(prio, 1, "boss priority")
    sigs = Learn.FromMeterRow(RFC, "Searing Blade Enforcer", "elite")
    t.eq(table.concat(sigs, ","), "elite|RAGE|917116,elite|RAGE|949470", "data: both bodies the Enforcer uses, stable order")
    zone.sigs["elite|RAGE|949470"] = { type = "TANK", prio = 3 }   -- only the second body has an entry
    meterRows = {
        { name = "Searing Blade Enforcer", classification = "elite" },
        { name = "Taragaman the Hungerer", classification = "elite" },
        { name = "Some Forever Mob", classification = "normal" },        -- not in the data: rules default
        { name = "Searing Blade Warlock", classification = "elite" },     -- exists: untouched
        { name = "Tankard Stoneforge", classification = "", isLocalPlayer = true },
        { name = sim:maybeSecret("Hidden", true), classification = "elite" },
    }
    sim:EnterCombat()
    sim:LeaveCombat()
    sim:Fire("PLAYER_REGEN_ENABLED")
    sim:Advance(3)
    t.eq(zone.names["Searing Blade Enforcer"] and zone.names["Searing Blade Enforcer"].prio, 3,
        "meter name copies the body entry it has, whichever body that is")
    t.eq(zone.names["Taragaman the Hungerer"] and zone.names["Taragaman the Hungerer"].prio, 1, "boss from the meter")
    t.ok(zone.names["Some Forever Mob"] ~= nil, "unknown mob: rules default while recording")
    t.eq(zone.names["Searing Blade Warlock"].prio, 9, "existing entry still untouched")
    t.eq(zone.names["Tankard Stoneforge"], nil, "the player is skipped")
    t.eq(#sim.errors, 0, "no Lua errors (secret name skipped)")

    -- Option off, or outside instances: the meter isn't read.
    meterRows = { { name = "Late Mob", classification = "elite" } }
    env.BulwarkDB.marking.learnNames = false
    t.eq(Learn:ReadMeter(), 0, "option off: meter ignored")
    env.BulwarkDB.marking.learnNames = true
    Plates.inInstance = false
    t.eq(Learn:ReadMeter(), 0, "open world: meter ignored")
    Plates.inInstance = true
    t.eq(Learn:ReadMeter(), 1, "dungeon, option on: read")

    -- The Mobs page lists the new name entries.
    local labels = {}
    for _, row in ipairs(MobDB:Entries("Ragefire Chasm")) do labels[row.label] = row.kind end
    t.eq(labels["Searing Blade Cultist"], "name", "Mobs page shows the learned name")
    t.eq(labels["casters"], "sig", "and still the body entry")
end
