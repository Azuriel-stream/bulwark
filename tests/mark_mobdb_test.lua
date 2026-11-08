-- Mob database: learning by name vs signature, sorting, edits, labels in plans, delete, the window's paging.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        -- Units flagged secretName behave like mobs inside an instance (name hidden).
        local realName = s.env.UnitName
        s.env.UnitName = function(u)
            local x = s.units[u]
            if x and x.secretName then return nil end
            return realName(u)
        end
    end)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local MobDB = MK.MobDB

    -- Open world: learned by name, default priority from the rules (normal melee = 5).
    sim.units.target.tier = "normal"
    local e, label = MobDB:Learn("target")
    t.eq(label, "Defias Pillager", "learned by name")
    t.eq(e.type, "TANK", "tank by default")
    t.eq(e.prio, 5, "rules priority for a normal melee")

    -- Instance-like: name hidden -> signature.
    sim.units.nameplate1 = { name = "Ragefire Shaman", secretName = true, guid = "Creature-0-1-0-1-11319-0000000002",
                             friendly = false, level = 13, tier = "elite", power = "MANA" }
    local e2, label2 = MobDB:Learn("nameplate1")
    t.eq(label2, "lvl 13 elite caster", "learned by signature")
    t.eq(e2.prio, 2, "rules priority for an elite caster")
    local zone = MK.db.mobs[MK.Plates.zone]
    t.ok(zone.sigs["13|elite|MANA"] == e2, "stored under its signature")

    -- Sorting: names first, then signatures by level.
    sim.units.nameplate2 = { name = "X", secretName = true, guid = "Creature-0-1-0-1-1-3", friendly = false,
                             level = 15, tier = "elite", power = "RAGE" }
    MobDB:Learn("nameplate2")
    local rows = MobDB:Entries(MK.Plates.zone)
    t.eq(rows[1].kind, "name", "names first")
    t.eq(rows[2].key, "15|elite|RAGE", "higher-level signature next")
    t.eq(rows[3].key, "13|elite|MANA", "then lower")

    -- Edits.
    MobDB:CycleType(e2)
    t.eq(e2.type, "CC", "Kill -> CC")
    MobDB:CycleClass(e2)
    t.eq(e2.class, "MAGE", "any -> Mage")
    for _ = 1, 5 do MobDB:CycleClass(e2) end
    t.eq(e2.class, "DRUID", "... -> Druid (no Shaman: no CC on Forever)")
    MobDB:CycleClass(e2)
    t.eq(e2.class, nil, "Druid -> any")
    MobDB:CycleType(e2)
    MobDB:CycleType(e2)
    t.eq(e2.type, "TANK", "Ignore -> Tank")
    for _ = 1, 12 do MobDB:StepPrio(e2, 1) end
    t.eq(e2.prio, 9, "priority capped at 9")
    for _ = 1, 12 do MobDB:StepPrio(e2, -1) end
    t.eq(e2.prio, 1, "priority floor 1")
    MobDB:CycleIcon(e2)
    t.eq(e2.icon, 8, "auto -> skull")
    MobDB:CycleIcon(e2)
    t.eq(e2.icon, 7, "skull -> cross")
    MobDB:ClearIcon(e2)
    t.eq(e2.icon, nil, "back to auto")

    -- A label on the signature shows up in plans.
    MobDB:SetNote(e2, "  Ragefire Shaman ")
    t.eq(e2.note, "Ragefire Shaman", "label trimmed")
    t.eq(MK.Planner.Describe(MK.Plates:Read("nameplate1", {})), "Ragefire Shaman", "plan shows the label")
    MobDB:SetNote(e2, "")
    t.eq(e2.note, nil, "empty label removed")

    -- Delete.
    MobDB:Delete(MK.Plates.zone, "sig", "15|elite|RAGE")
    t.eq(#MobDB:Entries(MK.Plates.zone), 2, "deleted")

    -- Mobs page: pages 10 rows at a time.
    for i = 1, 11 do zone.sigs[string.format("%d|normal|RAGE", 20 + i)] = { type = "TANK", prio = 5 } end
    local panel = H.page(sim, "mobs")
    t.ok(panel.frame:IsShown(), "page shown")
    t.eq(panel.pageText:GetText(), "Page 1/2", "13 entries -> 2 pages")
    panel.nextPage:Click()
    t.eq(panel.pageText:GetText(), "Page 2/2", "next page")
    t.ok(panel.rows[3]:IsShown() and not panel.rows[4]:IsShown(), "page 2 shows the last 3 entries")
end
