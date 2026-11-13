-- Alerts for Paladins on Forever: Judgement is the taunt while Seal of Fury is up (taunt effect 20232), otherwise a
-- threat ability; Holy Strike uses Forever's rank IDs; abilities that don't exist on Forever are gone.
-- Facts: kb/tanks/paladin.md.
return function(sim, t)
    -- Shaman list (default warrior client): only Forever abilities.
    local Spells = sim.env.Bulwark.AlertSpells
    t.eq(table.concat(Spells.Order.SHAMAN, ","), "Earth Shock,Frost Shock,Stormstrike", "Turtle-only Shaman spells gone")
    t.eq(table.concat(Spells.Order.PALADIN, ","), "Judgement,Holy Strike", "Paladin list")
    t.ok(Spells.Get("PALADIN", "Hand of Reckoning") == nil and Spells.Get("PALADIN", "Righteous Defense") == nil,
        "TBC taunts gone")

    local p = t.fresh(function(s)
        s.units.player.class = "PALADIN"
        s.spells[20271] = "Judgement"
        s.spells[10333] = "Holy Strike"
        s.spells[20423] = "Seal of Fury"
        s.spells[20293] = "Seal of Righteousness"
    end)
    local NS = p.env.Bulwark
    local AA = NS.AbilityAlerts

    local function newChat(fn)
        local before = #p.chat
        fn()
        p:Advance(0.01)
        local lines = {}
        for i = before + 1, #p.chat do lines[#lines + 1] = p.chat[i] end
        return lines
    end
    local function castAndAvoid(spellID, action)
        p:Advance(2)
        return newChat(function()
            p:Fire("UNIT_SPELLCAST_SENT", "player", "Defias Pillager", "Cast-1", spellID)
            p:Fire("UNIT_COMBAT", "target", action, "", 0, 1)
        end)
    end
    local function castSeal(id) p:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-S", id) end

    -- In combat with solid threat: a normal threat ability stays quiet, a taunt is always announced.
    p:EnterCombat()
    p.units.player.threatLead = 0
    t.ok(not AA.SealActive("FURY"), "no seal yet")
    t.eq(#castAndAvoid(20271, "RESIST"), 0, "Judgement without Seal of Fury = threat ability, quiet while solid")

    castSeal(20423)
    t.ok(AA.SealActive("FURY"), "Seal of Fury tracked from the cast (aura secret in combat)")
    local lines = castAndAvoid(20271, "RESIST")
    t.eq(#lines, 1, "Judgement with Seal of Fury = taunt, announced while solid")
    t.ok(lines[1].msg:find("[Judgement] RESISTED", 1, true), "message: " .. tostring(lines[1] and lines[1].msg))

    castSeal(20293)
    t.ok(not AA.SealActive("FURY"), "another seal replaces Seal of Fury")
    t.eq(#castAndAvoid(20271, "RESIST"), 0, "quiet again with Seal of Righteousness")

    castSeal(20423)
    p:Advance(31)
    t.ok(not AA.SealActive("FURY"), "Seal of Fury runs out after 30 s")

    -- Not solid: Holy Strike (Forever top rank 10333) dodge is announced.
    p.units.player.threatLead = 2
    lines = castAndAvoid(10333, "DODGE")
    t.eq(#lines, 1, "Holy Strike dodge announced")
    t.ok(lines[1].msg:find("[Holy Strike] DODGED", 1, true), "Holy Strike message")
    p:LeaveCombat()

    -- Out of combat the aura is readable: a seal cast before a /reload still counts.
    p.units.player.auras[#p.units.player.auras + 1] = { spellId = 20423, name = "Seal of Fury" }
    t.ok(AA.SealActive("FURY"), "Seal of Fury from the aura out of combat")

    -- Abilities page: the conditional taunt is labelled.
    p:Slash("/bwk alerts")
    NS.Window:Select("alerts", "abilities")
    local page
    for _, pg in ipairs(NS:GetArea("alerts").pages) do if pg.key == "abilities" then page = pg end end
    t.ok(page.boxes["Judgement"] and page.boxes["Holy Strike"], "both Paladin abilities on the page")
    t.ok(page.boxes["Hand of Reckoning"] == nil, "no TBC taunt on the page")
end
