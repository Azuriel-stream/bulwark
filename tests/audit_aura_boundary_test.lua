-- Combat start/end boundary: auras restricted while InCombatLockdown() is still false. The read then throws
-- ("Auras cannot be accessed when secret while tainted") [in-game 2026-11-08..12]. Audit must neither error nor
-- lose what it knows (plan, self-buff expiry).
local H = require("audit_helpers")

return function(_, t)
    local w = t.fresh(function(s)
        H.Party(s)
        s.known[6673] = true
    end)
    local env, NS = w.env, w.env.Bulwark
    table.insert(w.units.player.auras, H.Aura(6192, "Battle Shout", { duration = 180, expirationTime = w.now + 170 }))
    H.Rescan(w)
    w:Advance(1)
    local entry = NS.AuditSelfAlert:GetEntries()[1]
    local expiry = entry.expiresAt
    t.ok(expiry ~= nil, "expiry known out of combat")
    local plan = NS.AuditScanner.plan
    t.ok(plan and #plan.tiles > 0, "plan built")

    -- Model the boundary: reads throw while w.auraLock is set; Blizzard's predicate may or may not say so.
    local byIndex, bySpell = env.C_UnitAuras.GetAuraDataByIndex, env.C_UnitAuras.GetPlayerAuraBySpellID
    env.C_UnitAuras.GetAuraDataByIndex = function(...)
        if w.auraLock then error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'Bulwark'") end
        return byIndex(...)
    end
    env.C_UnitAuras.GetPlayerAuraBySpellID = function(...)
        if w.auraLock then error("GetPlayerAuraBySpellID(): Auras cannot be accessed when secret while tainted by 'Bulwark'") end
        return bySpell(...)
    end
    local predicateKnows = true
    env.C_Secrets.ShouldUnitAuraIndexBeSecret = function() return predicateKnows and w.auraLock == true end

    local errorsBefore = #w.errors
    w.auraLock = true
    H.Rescan(w)
    w:Advance(2)
    t.eq(#w.errors, errorsBefore, "no Lua error when Blizzard's predicate reports the aura secret")
    t.ok(NS.AuditScanner.plan == plan, "plan kept")
    t.eq(entry.expiresAt, expiry, "self-buff expiry kept")

    predicateKnows = false   -- the predicate disagrees with the read: the pcall still covers it
    H.Rescan(w)
    w:Advance(2)
    t.eq(#w.errors, errorsBefore, "no Lua error when only the read throws")
    t.eq(entry.expiresAt, expiry, "self-buff expiry still kept")

    w.auraLock = false
    H.Rescan(w)
    w:Advance(1)
    t.ok(NS.AuditScanner.plan ~= plan, "readable again: rescanned")
    t.eq(entry.expiresAt, expiry, "same aura, same expiry")
end
