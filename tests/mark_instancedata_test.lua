-- Offline instance data: (instance map, model file) -> creature type + CC immunities, so CC is legal and safe inside
-- instances where UnitCreatureType is secret. Variants are filtered by power type and level; disagreement = unknown.
local H = require("mark_helpers")

local RFC = 389
local TROGG, WORM, ORC_HD = 126239, 126512, 917116

local function setup(s)
    H.install(s)
    s.env.IsInInstance = function() return true, "party" end
    s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, RFC, 5, nil, false end
    s.env.UnitRace = function(u) local x = s.units[u]; if x then return "Human", "Human" end end
    s.units.party1.class = "MAGE"
    local realName = s.env.UnitName
    s.env.UnitName = function(u)   -- names hidden inside instances
        if u:find("^nameplate") then return nil end
        return realName(u)
    end
    s.units.target = nil
    -- No ctype on the units: UnitCreatureType reads nil, as inside an instance.
    s.units.nameplate1 = { guid = "Creature-0-1-0-1-11319-1", friendly = false, level = 14, tier = "elite",
                           power = "MANA", model = TROGG }   -- Ragefire Shaman
    s.units.nameplate2 = { guid = "Creature-0-1-0-1-11319-2", friendly = false, level = 13, tier = "elite",
                           power = "MANA", model = TROGG }   -- Ragefire Shaman
    s.units.nameplate3 = { guid = "Creature-0-1-0-1-11318-3", friendly = false, level = 15, tier = "elite",
                           power = "RAGE", model = TROGG }   -- Ragefire Trogg
end

local function plannedIcons(MK)
    local by = {}
    for _, e in ipairs(MK.Planner.plan.entries) do by[e.rec.token] = e.icon end
    return by
end

return function(_, t)
    -- Pure matching.
    local sim = t.fresh(setup)
    local MK = sim.env.Bulwark.Marking
    local Rules, data = MK.Rules, MK.InstanceMobs
    t.ok(data[RFC] and data[RFC][TROGG], "RFC trogg model in the generated data")

    local id = Rules.IdentifyFromData(data[RFC][TROGG], "RAGE", 14)
    t.eq(id.ctype, "Humanoid", "rage trogg body: humanoid")
    t.eq(table.concat(id.names, ","), "Ragefire Trogg", "level 14 excludes the boss on the same body")
    t.eq(id.immune, "", "trash trogg has no CC immunity")
    id = Rules.IdentifyFromData(data[RFC][TROGG], "RAGE", 16)
    t.eq(id.names[1], "Oggleflint", "level 16 rage trogg = the boss")
    t.ok(id.immune:find("P", 1, true), "boss is polymorph-immune")
    id = Rules.IdentifyFromData(data[RFC][TROGG], "MANA", 14)
    t.eq(id.names[1], "Ragefire Shaman", "mana trogg = shaman")
    t.eq(Rules.IdentifyFromData(data[RFC][WORM], "RAGE", 14).ctype, "Beast", "worm: beast")
    t.eq(Rules.IdentifyFromData(data[RFC][TROGG], "ENERGY", 14), nil, "power type no NPC has: unknown")

    local mixed = { "H;M;10;12;;;Cultist", "U;M;10;12;;B;Ghost", "U;R;10;12;FZ;B;Ghoul" }
    t.eq(Rules.IdentifyFromData(mixed, "RAGE", 11).boss, true, "only bosses match: boss")
    t.eq(Rules.IdentifyFromData(mixed, "MANA", 11).boss, false, "boss + trash on one body: not a boss")
    t.eq(Rules.IdentifyFromData(mixed, "MANA", 11).ctype, nil, "types disagree: unknown, never a guess")
    t.eq(Rules.IdentifyFromData(mixed, "RAGE", 11).ctype, "Undead", "power type separates them")
    id = Rules.IdentifyFromData(mixed, nil, 40)
    t.eq(id.ctype, nil, "no level match falls back to all variants (stricter)")
    t.eq(id.immune, "FZ", "immunities are the union")

    -- Immunity per class mechanic.
    t.ok(Rules.CCImmune("MAGE", "Humanoid", "FP"), "polymorph immunity blocks a mage")
    t.ok(not Rules.CCImmune("MAGE", "Humanoid", "F"), "fear immunity doesn't block a mage")
    t.ok(Rules.CCImmune("WARLOCK", "Elemental", "B"), "warlock on an elemental = banish")
    t.ok(not Rules.CCImmune("WARLOCK", "Humanoid", "B"), "warlock on a humanoid = fear")
    t.ok(Rules.CCImmune("ROGUE", "Humanoid", "K"), "sap blocked by knockout immunity")
    local slots = { { mark = 5, class = "MAGE", alive = true } }
    t.eq(Rules.SelectCCSlot(nil, "Humanoid", slots, false, "P"), nil, "no sheep on a polymorph-immune mob")
    t.eq(Rules.SelectCCSlot(nil, "Elemental", slots, false, nil), nil, "no sheep on an elemental")
    t.eq(Rules.SelectCCSlot("MAGE", nil, slots, true, "P"), nil, "taught CC still respects immunity")

    -- In the sim: kill ladder = skull only, moon = Lumen's sheep. The second shaman is a leftover caster (CC worth 70);
    -- its type comes from the data, so the sheep is legal.
    local rows = sim.env.BulwarkCharDB.marking.setup.rows
    for i = 2, 8 do rows[i].role = "OFF" end
    rows[4].role, rows[4].player = "CC", "Lumen Brightwater"
    MK.Plates.Changed()
    sim:Advance(2)
    local recs = MK.Plates.records
    t.eq(MK.Plates.instanceID, RFC, "instance map ID read")
    t.eq(recs.nameplate1.ctype, "Humanoid", "type restored from the data")
    t.eq(recs.nameplate1.ctypeSource, "data", "source recorded")
    t.eq(MK.MobDB:Label(recs.nameplate1), "Ragefire Shaman", "label uses the data name")
    local by = plannedIcons(MK)
    t.eq(by.nameplate2, 8, "lower-level shaman killed first")
    t.eq(by.nameplate1, 5, "second shaman sheeped")
    t.eq(by.nameplate3, nil, "trogg (melee) overflows")
    local reported = false
    sim:Slash("/bwk mark plan")
    for _, line in ipairs(sim.output) do if line:find("Humanoid (data)", 1, true) then reported = true end end
    t.ok(reported, "/bwk mark plan shows the data type")
    local overflowLine = false
    for _, line in ipairs(sim.output) do
        if line:find("no icon: Ragefire Trogg (out of icons", 1, true) then overflowLine = true end
    end
    t.ok(overflowLine, "/bwk mark plan names the mob without an icon and why")

    -- Plates left out of the plan are reported with the reason.
    MK.Plates.selected.nameplate1 = true
    MK.Plates.Changed()
    sim:Advance(1)
    sim:Slash("/bwk mark plan")
    local selLine = false
    for _, line in ipairs(sim.output) do
        if line:find("no icon: Ragefire Shaman (not in your Shift-hover selection)", 1, true) then selLine = true end
    end
    t.ok(selLine, "/bwk mark plan explains a plate outside the selection")
    MK.Plates:ClearSelection(true)

    -- A Shaman has no CC on Forever: the moon row with a Shaman gives no CC slot.
    sim.units.party1.class = "SHAMAN"
    t.eq(#MK.Team:GetCCSlots(), 0, "shaman CC row: no slot")
    t.ok(not Rules.HasCC("SHAMAN") and Rules.HasCC("MAGE"), "HasCC")
    sim.units.party1.class = "MAGE"
    MK.Plates.Changed()
    sim:Advance(1)

    -- Encounter bosses (the client calls them "elite") become tier boss from the data: killed before the trash, and
    -- their own signature, so a learned trash entry of the same body doesn't apply (Oggleflint vs Ragefire Trogg).
    local zone = MK:GetZoneMobs(MK.Plates.zone)
    zone.sigs["elite|RAGE|126239"] = { type = "TANK", prio = 4 }   -- the user's trogg entry
    sim.units.nameplate3 = { guid = "Creature-0-1-0-1-11517-3", friendly = false, level = 16, tier = "elite",
                             power = "RAGE", model = TROGG }   -- Oggleflint
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    sim:Advance(2)
    t.eq(recs.nameplate3.dataName, "Oggleflint", "boss named")
    t.eq(recs.nameplate3.tier, "boss", "boss tier from the data")
    t.eq(recs.nameplate3.sig, "boss|RAGE|126239", "own signature, not the trogg entry")
    t.eq(recs.nameplate1.tier, "elite", "shaman on the same body stays elite")
    by = plannedIcons(MK)
    t.eq(by.nameplate3, 8, "boss skull, ahead of the prio-2 shamans")
    t.eq(by.nameplate2, nil, "first shaman (lower level) out of kill icons...")
    t.eq(by.nameplate1, 5, "...the kill-last shaman still sheeped")
    sim:Slash("/bwk mark plan")
    local bossLine = false
    for _, line in ipairs(sim.output) do if line:find("Oggleflint (kill, prio 1", 1, true) and line:find("boss (data)", 1, true) then bossLine = true end end
    t.ok(bossLine, "/bwk mark plan shows the data boss")
    -- Jergosh (HD orc body shared with trash casters): boss, never CC'd.
    sim.units.nameplate3 = { guid = "Creature-0-1-0-1-11518-3", friendly = false, level = 16, tier = "elite",
                             power = "MANA", model = ORC_HD }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    sim:Advance(2)
    t.eq(recs.nameplate3.dataName, "Jergosh the Invoker", "Jergosh identified")
    t.eq(plannedIcons(MK).nameplate3, 8, "Jergosh skull")
    t.ok(not Rules.CCTierEligible(recs.nameplate3.tier), "boss tier is never CC'd")

    -- Mob database window: signature entries are named from the data (power, boss or not, levels seen).
    local MobDB = MK.MobDB
    zone.sigs["elite|RAGE|126239"].levels = { 13, 15 }
    zone.sigs["elite|MANA|126239"] = { type = "TANK", prio = 2, levels = { 14, 14 } }
    zone.sigs["boss|RAGE|126239"] = { type = "TANK", prio = 1, levels = { 16, 16 } }
    zone.sigs["elite|MANA|917116"] = { type = "TANK", prio = 2, levels = { 13, 15 } }
    zone.sigs["elite|RAGE|126512"] = { type = "TANK", prio = 4, note = "worms first" }
    zone.sigs["14|elite|MANA"] = { type = "TANK", prio = 2 }   -- model-less fallback entry
    MobDB.RememberInstance()
    t.eq(zone.instanceID, RFC, "zone remembers its instance")
    local labels = {}
    for _, row in ipairs(MobDB:Entries(MK.Plates.zone)) do labels[row.key] = row.label end
    t.eq(labels["elite|RAGE|126239"], "Ragefire Trogg", "trash entry: trogg only (boss excluded)")
    t.eq(MobDB.DefaultLabel(MK.Plates.zone, "elite|RAGE|126239", { type = "TANK" }), "Ragefire Trogg",
        "no levels recorded: the boss filter alone keeps Oggleflint out")
    t.eq(labels["elite|MANA|126239"], "Ragefire Shaman", "mana body: shaman")
    t.eq(labels["boss|RAGE|126239"], "Oggleflint", "boss entry")
    t.eq(labels["elite|MANA|917116"], "Searing Blade Cultist +1", "two casters share the HD orc body")
    t.eq(labels["elite|RAGE|126512"], "worms first", "the player's note wins")
    t.eq(labels["14|elite|MANA"], "lvl 14 elite caster", "no model: description")
    t.eq(table.concat(MobDB.DataNames(MK.Plates.zone, "elite|MANA|917116", zone.sigs["elite|MANA|917116"]), ","),
        "Searing Blade Cultist,Searing Blade Warlock", "all names for the tooltip")
    -- Browsing the zone from elsewhere still names it (remembered instance).
    MK.Plates.zone, MK.Plates.instanceID = "Orgrimmar", nil
    t.eq(MobDB.DefaultLabel("Test Zone", "elite|MANA|126239", zone.sigs["elite|MANA|126239"]), "Ragefire Shaman",
        "named from another zone")
    MK.Plates.zone, MK.Plates.instanceID = "Test Zone", RFC

    -- Open world (no data): readable creature type wins, no immunities.
    local sim2 = t.fresh(function(s)
        setup(s)
        s.env.IsInInstance = function() return false, "none" end
        s.env.GetInstanceInfo = function() return "Kalimdor", "none", 0, "", 0, 0, false, 1, 0, nil, false end
        s.units.nameplate1.ctype = "Beast"
    end)
    local rec = sim2.env.Bulwark.Marking.Plates.records.nameplate1
    t.eq(rec.ctype, "Beast", "unit type kept")
    t.eq(rec.ctypeSource, "unit", "from the unit")
    t.eq(rec.immune, nil, "no data outside instances")
end
