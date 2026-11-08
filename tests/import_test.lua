-- One-time import of the standalone addons' settings (Core/Import.lua): copied in, old copies dropped, never
-- imported twice; learned mobs merged without overwriting Bulwark's own.
local function legacy(s)
    s.env.TankAlertForeverDB = { global = { enabled = true, forceChannel = "raid", alertThrottle = 12,
        quietWhenThreatSolid = false, debugMode = true }, abilities = { WARRIOR = { ["Sunder Armor"] = false } } }
    s.env.TankAuditForeverDB = { enabled = true, locked = false, scale = 1.3, point = { "TOP", "TOP", 5, -50 },
        consumableLevel = 3, blessingPriority = { WARRIOR = { "MIGHT", "KINGS", "LIGHT", "WISDOM" } } }
    s.env.TankMarkForeverDB = { overlay = false, hud = { collapsed = true, point = { x = 10, y = 600 } },
        debug = true, errors = { { msg = "old" } },
        mobs = { ["The Wailing Caverns"] = { names = {}, sigs = {
            ["elite|MANA|123105"] = { type = "TANK", prio = 2 },
            ["boss|RAGE|123105"] = { type = "TANK", prio = 1 } } } } }
    s.env.TankMarkForeverCharDB = { setup = { rows = {
        { icon = 8, role = "TANK" }, { icon = 7, role = "TANK" }, { icon = 6, role = "CC", player = "Kurathos Bloodletter" },
        { icon = 5, role = "TANK", off = true }, { icon = 4, role = "TANK" }, { icon = 3, role = "TANK" },
        { icon = 2, role = "FOLLOW" }, { icon = 1, role = "TANK" } } } }
end

return function(sim, t)
    -- Nothing to import: nothing said.
    t.ok(not sim.env.BulwarkDB.imported.alerts, "fresh install imports nothing")

    -- Old data present (the migration script appended it to Bulwark's files).
    local s = t.fresh(function(x)
        legacy(x)
        -- Bulwark already learned one WC mob itself: it wins over the old entry.
        x.env.BulwarkDB = { marking = { mobs = { ["The Wailing Caverns"] = { names = {}, sigs = {
            ["boss|RAGE|123105"] = { type = "IGNORE" } } } } } }
    end)
    s:Advance(4)
    local db, char = s.env.BulwarkDB, s.env.BulwarkCharDB
    t.eq(db.alerts.forceChannel, "raid", "Alerts channel imported")
    t.eq(db.alerts.alertThrottle, 12, "Alerts throttle imported")
    t.eq(db.alerts.quietWhenThreatSolid, false, "Alerts quiet option imported")
    t.eq(db.alerts.abilities.WARRIOR["Sunder Armor"], false, "untracked ability imported")
    t.eq(db.alerts.enabled, nil, "TankAlert's own on/off not copied (the area switch replaces it)")
    t.eq(db.audit.locked, false, "Audit lock imported")
    t.eq(db.audit.scale, 1.3, "Audit size imported")
    t.eq(db.audit.point[1], "TOP", "Audit tile position imported")
    t.eq(db.audit.consumableLevel, 3, "consumables imported")
    t.eq(db.audit.blessingPriority.WARRIOR[1], "MIGHT", "blessing order imported")
    t.eq(db.marking.overlay, false, "Marking overlay imported")
    t.eq(db.marking.hud.point.y, 600, "HUD position imported")
    local wc = db.marking.mobs["The Wailing Caverns"].sigs
    t.eq(wc["elite|MANA|123105"].prio, 2, "learned mob added")
    t.eq(wc["boss|RAGE|123105"].type, "IGNORE", "Bulwark's own entry kept")
    t.eq(char.marking.setup.rows[3].player, "Kurathos Bloodletter", "team setup imported")
    t.eq(char.marking.setup.rows[4].off, true, "on/off imported")
    t.eq(db.debug, false, "TankMark's debug flag not copied")
    t.eq(#db.errors, 0, "TankMark's errors not copied")
    -- The areas use the imported values from the start.
    local Bar = s.env.Bulwark.AuditBar
    local p = { Bar:GetAnchor():GetPoint() }
    t.eq(p[1], "TOP", "Audit tiles built at the imported position")
    t.eq(s.env.Bulwark.Marking.Team:Rows()[3].role, "CC", "Marking uses the imported setup")
    -- Old copies dropped (nil = not written back), done flags set, one chat line.
    t.eq(s.env.TankAlertForeverDB, nil, "old Alerts copy dropped")
    t.eq(s.env.TankMarkForeverCharDB, nil, "old team copy dropped")
    t.ok(db.imported.alerts and db.imported.audit and db.imported.marking, "done flags")
    t.ok(char.importedSetup, "character done flag")
    t.contains(s.output, "Imported your settings", "player told")

    -- The old data again (e.g. the script run twice): not imported over the newer settings.
    local again = t.fresh(function(x)
        legacy(x)
        x.env.BulwarkDB = { imported = { alerts = "x", audit = "x", marking = "x" }, alerts = { forceChannel = "party" } }
        x.env.BulwarkCharDB = { importedSetup = "x" }
    end)
    again:Advance(4)
    t.eq(again.env.BulwarkDB.alerts.forceChannel, "party", "no second import")
    t.eq(again.env.BulwarkCharDB.marking.setup.rows[3].role, "TANK", "team setup not re-imported")
    t.eq(again.env.TankAuditForeverDB, nil, "old copies still dropped")
    for _, line in ipairs(again.output) do t.ok(not line:find("Imported"), "nothing said: " .. line) end
end
