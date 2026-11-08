-- "No tiles = all good": tiles appear only for missing/expiring buffs, and fade in during combat.
local H = require("audit_helpers")

return function(sim, t)
    local w = t.fresh(function(s)
        H.Party(s)
        s.known[6673] = true
        s.forms = { { spellID = 71, active = true } } -- already in Defensive Stance
        s.units.player.auras = {
            H.Aura(6192, "Battle Shout", { duration = 180, expirationTime = s.now + 170 }),
            H.Aura(1243, "Power Word: Fortitude", { duration = 3600, expirationTime = s.now + 100, sourceUnit = "party1" }),
            H.Aura(14752, "Divine Spirit", { duration = 3600, expirationTime = s.now + 3000 }),
            H.Aura(20217, "Blessing of Kings", { duration = 3600, expirationTime = s.now + 3000 }),
            H.Aura(465, "Devotion Aura", { duration = 0, expirationTime = 0 }),
            H.Aura(19705, "Well Fed", { duration = 900, expirationTime = s.now + 900 }),
        }
        s.weaponEnchants[0] = { { hasEnchant = true, timeLeft = 1800 * 1000, enchantID = 1 } }
    end)
    H.Rescan(w)
    t.eq(#H.Shown(w), 0, "fully buffed: no tiles (" .. H.Keys(w) .. ")")
    local fortTile = H.Planned(w, "GROUP:FORTITUDE")
    t.ok(fortTile, "Fortitude tile waits invisibly")
    -- No phantom tooltips over hidden tiles: our tile and Blizzard's aura button both ignore the mouse
    t.ok(not fortTile:IsMouseEnabled(), "hidden tile ignores the mouse")
    t.ok(not fortTile.blizzardSlot:IsMouseEnabled(), "Blizzard's aura button ignores the mouse (no tooltip)")
    local weaponTile = H.Planned(w, "CONS:WEAPON_BUFF")
    t.ok(weaponTile and not weaponTile.blizzardSlot:IsMouseEnabled(), "weapon enchant button ignores the mouse too")
    local salv = H.Container(w, w.env.Bulwark.AuditBar:GetSalvationHolder())._slots.unwanted
    t.ok(salv:IsMouseEnabled(), "Salvation keeps its mouse (right-click cancel)")
    -- Right-click (hold to turn the character) goes through our tiles to the world, even over a transparent
    -- debuff click-catcher that keeps its mouse in combat; left-click still reaches the tile.
    local catcher = w.env.Bulwark_AuditDebuffClickMagic
    t.ok(catcher and catcher:ShouldButtonPassThrough("RightButton"), "debuff catcher passes right-click through")
    t.ok(catcher and not catcher:ShouldButtonPassThrough("LeftButton"), "debuff catcher keeps left-click")
    t.ok(fortTile:ShouldButtonPassThrough("RightButton"), "buff tile passes right-click through")

    -- Expiring out of combat: visible, clickable, and a request says when it fades
    w.units.player.auras[2].expirationTime = w.now + 50
    H.Rescan(w)
    local expiring = H.Find(w, "GROUP:FORTITUDE")
    t.ok(expiring and expiring:IsMouseEnabled(), "expiring Fortitude shown and clickable")
    expiring:Click()
    t.ok(w.chat[#w.chat] and w.chat[#w.chat].msg:find("fading in"), "request mentions it's fading")
    w.units.player.auras[2].expirationTime = w.now + 100
    H.Rescan(w)
    t.ok(not H.Find(w, "GROUP:FORTITUDE"), "rebuffed: hidden again")

    -- Combat: Fortitude (100 s left at the pull) fades in at 60 s, from the pre-combat expiry
    w:EnterCombat()
    w:Advance(30)
    t.ok(not H.Find(w, "GROUP:FORTITUDE"), "70 s left: still hidden")
    w:Advance(15)
    t.ok(H.Find(w, "GROUP:FORTITUDE"), "under 60 s: Fortitude fades in, in combat")

    -- Battle Shout fades in at 15 s, then a recast (own cast, readable) hides it again, in combat
    w:Advance(115)
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "Battle Shout under 15 s: shown")
    w:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-6192-01", 6192)
    w.units.player.auras[1].expirationTime = w.now + 180 -- the cast refreshes the real buff too
    w:Advance(1)
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "recast in combat: hidden again")

    -- Someone refreshes Fortitude mid-fight: we can't know in combat, so the tile stays (Blizzard shows it lit)...
    w.units.player.auras[2].expirationTime = w.now + 3600
    w:Advance(2)
    t.ok(H.Find(w, "GROUP:FORTITUDE"), "in combat a shown group tile stays shown")
    t.eq(#w.violations, 0, "only alpha changed in combat (no protected changes)")

    -- ...and after combat the real aura is read again: hidden
    w:LeaveCombat()
    w:Advance(1)
    t.ok(not H.Find(w, "GROUP:FORTITUDE"), "after combat: refreshed Fortitude hidden")
    t.eq(#H.Shown(w), 0, "all good again: no tiles (" .. H.Keys(w) .. ")")

    -- A missing buff is shown, and clickable
    table.remove(w.units.player.auras, 6) -- Well Fed gone
    H.Rescan(w)
    local food = H.Find(w, "CONS:WELL_FED")
    t.ok(food and food:IsMouseEnabled(), "missing food shown and clickable")
end
