-- Self buffs other players can put on you (Battle Shout): someone else's copy counts only when it's at least as
-- strong as yours; a weaker one shows the tile as missing (user 2026-11-14).
local H = require("audit_helpers")

return function(sim, t)
    local w = t.fresh(function(s)
        H.Party(s)
        s.known[6673], s.known[5242], s.known[6192] = true, true, true   -- Battle Shout ranks 1-3 (base 33 AP)
    end)
    local NS = w.env.Bulwark
    local auras = w.units.player.auras
    local function BS(id, opts)
        local a = H.Aura(id, "Battle Shout", opts)
        a.duration, a.expirationTime = 180, w.now + 170
        return a
    end
    local function Set(aura)
        for i = #auras, 1, -1 do auras[i] = nil end
        if aura then auras[1] = aura end
        H.Rescan(w)
    end
    local def = NS.AuditData.SELF.WARRIOR[1]
    local tile = NS.AuditBar:GetTile("SELF:BATTLE_SHOUT")
    local slot = H.Container(w, tile)._slots.tile

    Set(nil)
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "no Battle Shout: tile shown")
    local mine, base = NS.AuditScanner.OwnStrength(def)
    t.eq(mine, 33, "untested yet: your strength = best known rank's base")
    t.eq(base, 33, "base of rank 3")

    -- Another warrior's weaker shout (rank 2, real value readable): missing, with its icon hidden
    Set(BS(5242, { sourceUnit = "party1", points = { 21 } }))
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "weaker shout from someone else: tile shown")
    t.eq(tile.item.weaker and tile.item.weaker.theirs, 21, "tooltip data: theirs")
    t.eq(tile.item.weaker and tile.item.weaker.mine, 33, "tooltip data: yours")
    t.eq(slot:GetAlpha(), 0, "Blizzard slot hidden so the red 'missing' art shows")
    t.eq(tile:GetAttribute("spell"), "Battle Shout", "click still casts yours")

    -- Stronger (talented rank 3) or equal: covered, no tile
    Set(BS(6192, { sourceUnit = "party1", points = { 41 } }))
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "stronger shout from someone else: no tile")
    t.eq(slot:GetAlpha(), 1, "slot shown again")
    Set(BS(6192, { sourceUnit = "party1", points = { 33 } }))
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "equal shout: no tile")

    -- No readable value: compare rank base values
    Set(BS(6192, { sourceUnit = "party1" }))
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "same rank, no value: no tile")
    Set(BS(5242, { sourceUnit = "party1" }))
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "lower rank, no value: tile shown")

    -- The 15-min 200 AP "Battle Shout" (25101, not a player rank; user 2026-11-19): no source unit (group gone),
    -- 6 min left. It counts as a stronger shout, with or without a readable value.
    local function NpcShout(points)
        local a = BS(25101, { points = points })
        a.duration, a.expirationTime = 900, w.now + 360
        return a
    end
    Set(NpcShout({ 200 }))
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "200 AP non-player shout: no tile")
    t.eq(tile.item.weaker, nil, "200 AP non-player shout: not weaker")
    Set(NpcShout(nil))
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "200 AP non-player shout, no value: base 200 beats yours")
    local inGroupList = false
    for _, g in ipairs(NS.AuditData.GROUP) do
        if g.key == "BATTLE_SHOUT" then
            for _, id in ipairs(g.ids) do inGroupList = inGroupList or id == 25101 end
        end
    end
    t.ok(inGroupList, "group Battle Shout (paladin tanks) knows 25101 too")

    -- Your own shout teaches its real value (talents); then an untalented rank 3 is weaker than yours
    Set(BS(6192, { sourceUnit = "player", points = { 41 } }))
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "your own shout: no tile")
    t.eq(NS.AuditScanner.OwnStrength(def), 41, "learned your talented value")
    Set(BS(6192, { sourceUnit = "party1", points = { 33 } }))
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "same rank without your talent: weaker, tile shown")

    -- A new rank you haven't cast yet: its base scaled by your talent ratio (51 * 41/33 = 63)
    w.known[11549] = true
    t.eq(NS.AuditScanner.OwnStrength(def), 63, "new rank estimated with your talent ratio")
    w.known[11549] = nil

    -- In combat: casting yours over the weaker one shows the slot again and fades the tile out
    Set(BS(5242, { sourceUnit = "party1", points = { 21 } }))
    t.eq(slot:GetAlpha(), 0, "weaker: slot hidden before the pull")
    w:EnterCombat()
    w:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-6192-01", 6192)
    w:Advance(1)
    t.eq(slot:GetAlpha(), 1, "your cast: slot shown in combat")
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "your cast: tile fades out in combat")
    w:LeaveCombat()
    w:Advance(1)

    -- Someone else's stronger shout: no in-combat sound when it runs low (its refreshes are invisible in combat)
    local before = #w.sounds
    local other = BS(6192, { sourceUnit = "party1", points = { 50 } })
    other.expirationTime = w.now + 30
    Set(other)
    w:EnterCombat()
    w:Advance(25)
    t.eq(#w.sounds, before, "no warning sound for someone else's shout")
    w:LeaveCombat()
    t.eq(#w.violations, 0, "no protected-frame violations")
end
