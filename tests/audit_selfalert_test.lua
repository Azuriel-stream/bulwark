-- In-combat self-buff warning: cast-timed sound + glow on the Battle Shout tile.
local H = require("audit_helpers")

return function(sim, t)
    local w = t.fresh(function(s)
        H.Party(s)
        s.known[6673] = true
    end)
    local NS = w.env.Bulwark
    local entries = NS.AuditSelfAlert:GetEntries()
    t.eq(#entries, 1, "warrior alerts on one buff")
    local e = entries[1]
    t.eq(e.def.key, "BATTLE_SHOUT", "alert on Battle Shout")
    t.eq(e.tile, NS.AuditBar:GetTile("SELF:BATTLE_SHOUT"), "glow lives on the Battle Shout tile")

    -- Out of combat: real duration and expiry learned from the readable aura
    table.insert(w.units.player.auras, H.Aura(6192, "Battle Shout", { duration = 180, expirationTime = w.now + 170 }))
    w:Advance(1)
    t.eq(NS.db.audit.watchDurations[6192], 180, "real duration learned out of combat")

    -- In combat: estimate keeps counting, warns once at ~15 s
    w:EnterCombat()
    w:Advance(150)
    t.eq(#w.sounds, 0, "no warning while plenty of time is left")
    w:Advance(10)
    t.eq(#w.sounds, 1, "warning sound at ~15 s left")
    t.ok(e.tile.glow:IsShown(), "tile glows")
    w:Advance(3)
    t.eq(#w.sounds, 1, "warns once, not every tick")

    -- Recast in combat restarts the estimate (own casts aren't secret)
    w:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-6192-01", 6192)
    t.ok(not e.tile.glow:IsShown(), "recast clears the glow")
    w:Advance(170)
    t.eq(#w.sounds, 2, "warns again before the recast buff runs out")

    -- Sound off: glow only
    NS.db.audit.watchSound = false
    w:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-6192-02", 6192)
    w:Advance(170)
    t.eq(#w.sounds, 2, "no sound when disabled")
    t.ok(e.tile.glow:IsShown(), "glow still shown")

    w:LeaveCombat()
    w:Advance(1)
    t.ok(not e.tile.glow:IsShown(), "glow hidden out of combat")
    t.eq(#w.violations, 0, "no protected-frame violations")
end
