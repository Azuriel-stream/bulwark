-- Paladin tank: self-castable tiles, Salvation cancel slot, own dispel types, unsupported classes.
local H = require("audit_helpers")

return function(sim, t)
    local p = t.fresh(function(s)
        s.units.player.class = "PALADIN"
        H.Party(s)
        s.known[25780] = true   -- Righteous Fury
        s.known[465] = true     -- Devotion Aura
        s.known[20217] = true   -- Blessing of Kings
        s.known[4987] = true    -- Cleanse
    end)
    H.Rescan(p)
    local keys = H.Keys(p)

    local rf = H.Find(p, "SELF:RIGHTEOUS_FURY")
    t.ok(rf and rf:GetAttribute("spell") == "Righteous Fury", "Righteous Fury tile casts: " .. keys)
    local aura = H.Find(p, "GROUP:PALADIN_AURA")
    t.ok(aura and aura:GetAttribute("spell") == "Devotion Aura", "paladin casts Devotion Aura itself")

    -- Two paladins (player + party2): paladin priority starts Kings, Wisdom
    local kings = H.Find(p, "BLESSING:KINGS")
    t.ok(kings and kings:GetAttribute("type") == "spell", "Kings is self-castable")
    local wisdom = H.Find(p, "BLESSING:WISDOM")
    t.ok(wisdom and wisdom:GetAttribute("type") == nil, "Wisdom (not known) is requested")
    t.ok(not H.Find(p, "GROUP:BATTLE_SHOUT"), "no warrior in group -> no Battle Shout")
    t.ok(H.Find(p, "GROUP:SPIRIT"), "paladin (mana) still checks Divine Spirit")
    t.ok(not H.Find(p, "SELF:BATTLE_SHOUT"), "paladin has no Battle Shout self tile")

    -- Salvation slot: Blizzard right-click cancel, filtered to Salvation (+ Greater)
    local Bar = p.env.Bulwark.AuditBar
    local salv = H.Container(p, Bar:GetSalvationHolder())._slots.unwanted
    t.ok(salv._options.candidateFilters.includeSpellIDs[1038], "Salvation slot includes Blessing of Salvation")
    t.ok(salv._options.candidateFilters.includeSpellIDs[25895], "...and Greater Blessing of Salvation")
    t.eq(salv._SetCancelAuraButtons.obj, "RightButtonUp", "right-click cancels")

    -- Own Cleanse covers Magic/Poison/Disease: clicking the debuff tile casts Cleanse on yourself (in combat too)
    for _, dtype in ipairs({ "Magic", "Poison", "Disease" }) do
        local tile = Bar:GetDebuffTile(dtype)
        t.ok(tile:IsShown(), dtype .. " tile shown")
        t.eq(tile.catcher:GetAttribute("spell"), "Cleanse", dtype .. " tile casts Cleanse")
    end
    t.ok(not Bar:GetDebuffTile("Curse"):IsShown(), "nobody removes curses -> no Curse tile")
    p:EnterCombat()
    Bar:GetDebuffTile("Poison").catcher:Click()
    t.eq(p.casts[#p.casts].spell, "Cleanse", "click on the Poison tile casts Cleanse in combat")
    t.eq(p.casts[#p.casts].unit, "player", "...on yourself")
    p:LeaveCombat()

    -- Unsupported class: no bar, a clear message
    local mage = t.fresh(function(s) s.units.player.class = "MAGE" end)
    mage:Slash("/bwk audit status")
    t.contains(mage.output, "supported yet", "unsupported class is told so")
    t.eq(#mage.env.Bulwark.AuditBar:GetTiles(), 0, "no tiles built for unsupported classes")
end
