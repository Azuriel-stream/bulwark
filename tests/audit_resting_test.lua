-- Resting (city or inn): buff, stance, consumable and healthstone tiles hide; gear warnings and debuffs stay.
local H = require("audit_helpers")

return function(sim, t)
    local w = t.fresh(function(s)
        H.Party(s)
        s.known[6673] = true                          -- Battle Shout learned, not up
        s.forms = { { spellID = 71, active = true } } -- Defensive Stance
        s.equipped[17] = nil                          -- no shield: a gear warning
    end)
    t.eq(w.env.BulwarkDB.audit.hideResting, true, "hide while resting: on by default")
    H.Rescan(w)
    for _, key in ipairs({ "SELF:BATTLE_SHOUT", "GROUP:FORTITUDE", "CONS:WELL_FED", "GEAR:NO_SHIELD" }) do
        t.ok(H.Find(w, key), "not resting: " .. key .. " expected in: " .. H.Keys(w))
    end

    -- Enter an inn: the resting event alone replans
    w.resting = true
    w:Fire("PLAYER_UPDATE_RESTING")
    w:Advance(1)
    t.eq(H.Keys(w), "GEAR:NO_SHIELD", "resting: only the gear warning is left")
    t.ok(not H.Planned(w, "SELF:BATTLE_SHOUT"), "resting: buff tiles not even waiting invisibly")

    -- Preview (Edit Mode / unlocked / options open) still shows every tile, so the bar can be placed in town
    w.env.Bulwark.AuditBar:SetPreview(true)
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "preview while resting shows all tiles")
    w.env.Bulwark.AuditBar:SetPreview(false)

    -- Setting off: tiles back while resting
    w.env.BulwarkDB.audit.hideResting = false
    H.Rescan(w)
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "setting off: tiles show while resting")
    w.env.BulwarkDB.audit.hideResting = true

    -- Leave the inn: back
    w.resting = false
    w:Fire("PLAYER_UPDATE_RESTING")
    w:Advance(1)
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT") and H.Find(w, "GROUP:FORTITUDE"), "left the inn: tiles back: " .. H.Keys(w))
end
