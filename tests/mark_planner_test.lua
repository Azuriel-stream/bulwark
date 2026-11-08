-- Pure planner: knowledge layering (name > signature > rules), ladder, fixed icons, reserved icons, CC pass.
local H = require("mark_helpers")

return function(sim, t)
    local P = sim.env.Bulwark.Marking.Planner
    local LADDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
    local function icons(plan)
        local by = {}
        for _, e in ipairs(plan.entries) do by[e.rec.token] = e.icon end
        return by
    end

    -- Rules only (instance: names secret): the mana user is killed first, then lower level first (dies faster).
    local melee14 = H.rec("nameplate1", { level = 14 })
    local caster13 = H.rec("nameplate2", { level = 13, power = "MANA" })
    local melee15 = H.rec("nameplate3", { level = 15 })
    local plan = P.Build({ melee14, caster13, melee15 }, nil, { ladder = LADDER })
    local by = icons(plan)
    t.eq(by.nameplate2, 8, "caster gets skull by rules")
    t.eq(by.nameplate1, 7, "lower-level melee next")
    t.eq(by.nameplate3, 6, "higher-level melee last")
    t.eq(table.concat(plan.killOrder, ","), "nameplate2,nameplate1,nameplate3", "kill order follows priority")

    -- Shift-hover order beats level and plate order among equal priority: the first hovered keeps skull.
    melee15.pick, melee14.pick = 1, 2
    by = icons(P.Build({ melee14, melee15 }, nil, { ladder = LADDER }))
    t.eq(by.nameplate3, 8, "first hovered keeps skull (although higher level)")
    t.eq(by.nameplate1, 7, "second hovered gets cross")
    caster13.pick = 3
    by = icons(P.Build({ melee14, caster13, melee15 }, nil, { ladder = LADDER }))
    t.eq(by.nameplate2, 8, "higher priority still takes skull, whatever the hover order")
    melee14.pick, melee15.pick, caster13.pick = nil, nil, nil

    -- Learned by signature beats rules; learned by name beats signature.
    local zone = { names = {}, sigs = { [melee14.sig] = { type = "TANK", prio = 1 } } }
    by = icons(P.Build({ melee14, caster13 }, zone, { ladder = LADDER }))
    t.eq(by.nameplate1, 8, "signature prio 1 beats the caster rule")
    local named = H.rec("nameplate4", { name = "Taragaman", level = 14 })
    zone.names["Taragaman"] = { type = "TANK", prio = 9 }
    by = icons(P.Build({ named, caster13 }, zone, { ladder = LADDER }))
    t.eq(by.nameplate2, 8, "name entry (prio 9) beats the signature entry (prio 1)")

    -- IGNORE, fixed icon, reserved icon.
    zone = { names = {}, sigs = { [melee14.sig] = { type = "IGNORE" }, [caster13.sig] = { type = "TANK", prio = 5, icon = 5 } } }
    plan = P.Build({ melee14, caster13, melee15 }, zone, { ladder = LADDER, reserved = { [8] = true } })
    by = icons(plan)
    t.eq(by.nameplate1, nil, "ignored mob gets no icon")
    t.eq(by.nameplate2, 5, "fixed icon honoured")
    t.eq(by.nameplate3, 7, "reserved skull skipped")
    t.ok(plan.reserved[8], "plan carries reserved icons")

    -- Short ladder: overflow, then CC on a legal slot (open world: creature type known).
    local slots = { { mark = 5, class = "MAGE", alive = true } }
    local a = H.rec("nameplate1", { level = 14, power = "MANA", ctype = "Humanoid" })
    local b = H.rec("nameplate2", { level = 15, power = "MANA", ctype = "Humanoid" })
    local m = H.rec("nameplate3", { level = 14 })
    plan = P.Build({ a, b, m }, nil, { ladder = { 8 }, ccSlots = slots })
    by = icons(plan)
    t.eq(by.nameplate1, 8, "first caster killed")
    t.eq(by.nameplate2, 5, "second caster sheeped (CC worthiness 70)")
    t.eq(#plan.overflow, 1, "melee overflow")
    -- Instances: unknown creature type, no authored class -> no CC.
    b.ctype = nil
    plan = P.Build({ a, b, m }, nil, { ladder = { 8 }, ccSlots = slots })
    t.eq(icons(plan).nameplate2, nil, "no CC without a creature type")
    t.eq(#plan.overflow, 2, "both leftovers reported")

    -- A mob taught as CC that no CC mark fits still gets a tank mark (it dies too).
    local trogg = H.rec("nameplate1", { level = 14 })
    local shaman = H.rec("nameplate2", { level = 14, power = "MANA", name = "Ragefire Shaman" })
    zone = { names = { ["Ragefire Shaman"] = { type = "CC", prio = 9 } }, sigs = {} }
    plan = P.Build({ trogg, shaman }, zone, { ladder = { 8, 7 }, ccSlots = slots, reserved = { [5] = true } })
    by = icons(plan)
    t.eq(by.nameplate1, 8, "trogg tanked on skull")
    t.eq(by.nameplate2, 7, "CC mob whose moon is taken falls back to cross")
    t.eq(plan.entries[2].reason, "cc-fallback", "reason shown in /tmf plan")
    t.eq(table.concat(plan.killOrder, ","), "nameplate1,nameplate2", "fallback mob joins the kill order")
    t.eq(#plan.overflow, 0, "nothing dropped")
    by = icons(P.Build({ trogg, shaman }, zone, { ladder = { 8, 7 }, ccSlots = slots }))
    t.eq(by.nameplate2, 5, "with moon free it's sheeped as taught")
    by = icons(P.Build({ trogg, shaman }, zone, { ladder = { 8 }, ccSlots = slots, reserved = { [5] = true } }))
    t.eq(by.nameplate2, nil, "no tank mark left either: overflow")

    -- Describe without a name.
    t.eq(P.Describe(caster13), "lvl 13 elite caster", "secret-name description")
end
