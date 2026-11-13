-- Gear warning tiles (Utilities feature 8, as Audit tiles): defense skill not maxed (groups only), tanking without a
-- shield (Defensive Stance / Righteous Fury), low durability. Only shown while something is wrong.
local H = require("audit_helpers")

return function(sim, t)
    local w = t.fresh(function(s)
        H.Party(s)
        s.forms = { { spellID = 71, active = true } }   -- Defensive Stance
    end)
    local audit = w.env.BulwarkDB.audit
    t.ok(audit.checkDefenseSkill and audit.checkShield and audit.checkDurability, "gear checks on by default")
    t.eq(audit.durabilityWarn, 25, "durability warning at 25 %")
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:NO_SHIELD") and not H.Find(w, "GEAR:DEFENSE_SKILL") and not H.Find(w, "GEAR:DURABILITY"),
        "all fine: no gear tiles: " .. H.Keys(w))

    -- Defense skill below 300 at level 60, in a group: tile; the detail mentions crushing blows while gear doesn't
    -- make up the difference.
    w.stats.defense = 290
    H.Rescan(w)
    local tile = H.Find(w, "GEAR:DEFENSE_SKILL")
    t.ok(tile, "defense skill 290/300: tile: " .. H.Keys(w))
    t.ok(tile and tile.item.detail:find("290 / 300", 1, true) and tile.item.detail:find("crushing", 1, true),
        "detail: " .. tostring(tile and tile.item.detail))
    w.stats.defenseMod = 20
    H.Rescan(w)
    tile = H.Find(w, "GEAR:DEFENSE_SKILL")
    t.ok(tile and not tile.item.detail:find("crushing", 1, true), "gear covers it: no crushing note")
    w.group = "none"
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:DEFENSE_SKILL"), "solo: no defense skill tile")
    w.group = "party"
    audit.checkDefenseSkill = false
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:DEFENSE_SKILL"), "switched off: no tile")
    audit.checkDefenseSkill = true
    -- One point short counts as maxed (the last point is very slow and worth 0.04 %); two points short is a tile.
    w.stats.defense, w.stats.defenseMod = 299, 0
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:DEFENSE_SKILL"), "299/300: no tile: " .. H.Keys(w))
    w.stats.defense = 298
    H.Rescan(w)
    t.ok(H.Find(w, "GEAR:DEFENSE_SKILL"), "298/300: tile")
    w.stats.defense = 300

    -- No shield in Defensive Stance: tile; out of the stance: nothing.
    w.equipped[17] = nil
    H.Rescan(w)
    tile = H.Find(w, "GEAR:NO_SHIELD")
    t.ok(tile, "Defensive Stance, no shield: tile: " .. H.Keys(w))
    t.ok(tile and tile.item.detail and tile.item.detail:find("without a shield", 1, true), "no-shield detail")
    w.forms = { { spellID = 2457, active = true } }   -- Battle Stance
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:NO_SHIELD"), "not tanking: no shield tile")

    -- Durability: lowest item at or below 25 %.
    w.durability = { [7] = { 30, 100 }, [5] = { 90, 100 } }
    w.equipped[7] = "|cffffffff|Hitem:10001::::::::|h[Dual Reinforced Leggings]|h|r"
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:DURABILITY"), "30 %: fine")
    w.durability[7] = { 20, 100 }
    H.Rescan(w)
    tile = H.Find(w, "GEAR:DURABILITY")
    t.ok(tile and tile.item.detail:find("Dual Reinforced Leggings is at 20%", 1, true),
        "20 %: tile naming the item: " .. tostring(tile and tile.item.detail))
    audit.durabilityWarn = 15
    H.Rescan(w)
    t.ok(not H.Find(w, "GEAR:DURABILITY"), "threshold 15 %: fine again")

    -- Paladin with Righteous Fury and no shield.
    local p = t.fresh(function(s)
        H.Party(s)
        s.units.player.class = "PALADIN"
        s.equipped[17] = nil
        s.units.player.auras = { H.Aura(25780, "Righteous Fury", { duration = 1800, expirationTime = s.now + 1700 }) }
    end)
    H.Rescan(p)
    t.ok(H.Find(p, "GEAR:NO_SHIELD"), "Righteous Fury, no shield: tile: " .. H.Keys(p))

    -- The Gear page builds and its switches work.
    w:Slash("/bwk")
    w.env.Bulwark.Window:Select("audit", "gear")
    local page
    for _, pg in ipairs(w.env.Bulwark:GetArea("audit").pages) do if pg.key == "gear" then page = pg end end
    t.ok(page and page.frame and page.frame:IsShown(), "Audit > Gear page shown")
    page.checks.checkDurability:Click()
    t.eq(audit.checkDurability, false, "durability switch saved")
    t.eq(#w.errors, 0, "no Lua errors")
end
