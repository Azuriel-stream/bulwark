-- Scroll tiles (user 2026-11-22): a scroll in your bags for a buff nobody in the group gives you; click = use it on
-- yourself. Stamina/Intellect/Spirit only without their provider class; Strength/Agility/Protection always (they
-- stack with shaman totems [in-game 2026-11-22]).
local H = require("audit_helpers")

local STAM_IV, STAM_III, PROT_II, AGI_IV, INT_IV, STR_IV = 10307, 4422, 1478, 10309, 10308, 10310

local function Bags(s)
    s.items[STAM_IV], s.items[STAM_III], s.items[PROT_II], s.items[AGI_IV], s.items[INT_IV] = 1, 3, 2, 1, 1
    s.itemNames[STAM_IV], s.itemNames[PROT_II] = "Scroll of Stamina IV", "Scroll of Protection II"
end

return function(sim, t)
    -- Warrior with a priest (party1) and a paladin: Stamina is the priest's job, Intellect isn't for warriors
    local w = t.fresh(function(s) H.Party(s); Bags(s) end)
    H.Rescan(w)
    local keys = H.Keys(w)
    t.ok(not H.Find(w, "SCROLL:STAMINA"), "priest in the group: no Stamina scroll: " .. keys)
    t.ok(not H.Find(w, "SCROLL:INTELLECT"), "warrior: no Intellect scroll: " .. keys)
    t.ok(not H.Find(w, "SCROLL:STRENGTH"), "no Strength scroll carried: no tile: " .. keys)
    t.ok(H.Find(w, "SCROLL:AGILITY"), "Agility scroll offered (no class gives it): " .. keys)

    local prot = H.Find(w, "SCROLL:PROTECTION")
    t.ok(prot, "Protection scroll offered: " .. keys)
    t.eq(prot:GetAttribute("type"), "item", "scroll tile uses an item")
    t.eq(prot:GetAttribute("item"), "item:" .. PROT_II, "uses the Protection scroll in the bags")
    t.eq(prot:GetAttribute("unit"), "player", "on yourself, never your target")
    t.eq(prot:GetAttribute("spell"), nil, "no spell attribute left over")
    t.eq(prot.item.label, "Scroll of Protection II", "label = the scroll's name")
    prot:Click()
    local last = w.casts[#w.casts]
    t.ok(last and last.item == "item:" .. PROT_II and last.unit == "player", "click uses the scroll on yourself")
    local slot = H.Container(w, prot)._slots.tile
    for _, id in ipairs({ 8091, 8094, 8095, 12175 }) do
        t.ok(slot._options.candidateFilters.includeSpellIDs[id], "Protection slot shows Armor rank " .. id)
    end
    t.ok(not slot._options.candidateFilters.includeSpellIDs[11349], "Elixir of Defense (also \"Armor\") isn't a scroll")

    -- No priest: Stamina offered, best usable rank first
    local np = t.fresh(function(s) H.Party(s); Bags(s); s.units.party1.class = "ROGUE" end)
    H.Rescan(np)
    local stam = H.Find(np, "SCROLL:STAMINA")
    t.ok(stam, "no priest: Stamina scroll offered: " .. H.Keys(np))
    t.eq(stam:GetAttribute("item"), "item:" .. STAM_IV, "best rank (IV) used")
    np.unusableItems[STAM_IV] = true
    H.Rescan(np)
    t.eq(H.Find(np, "SCROLL:STAMINA"):GetAttribute("item"), "item:" .. STAM_III, "level too low for IV: III used")
    t.eq(H.Find(np, "SCROLL:STAMINA").item.label, "Scroll of Stamina", "uncached name: generic label")

    -- Fortitude already on you (a priest buffed you, then left): no Stamina scroll
    np.units.player.auras = { H.Aura(10938, "Power Word: Fortitude") }
    H.Rescan(np)
    t.ok(not H.Find(np, "SCROLL:STAMINA") and not H.Planned(np, "SCROLL:STAMINA"), "Fortitude up: no Stamina scroll")

    -- Scroll buff up for 30 min: planned but waiting (fades in near expiry); a totem on the same stat stacks: tile stays
    np.units.player.auras = { H.Aura(12178, "Stamina", { expirationTime = np.now + 1800, duration = 1800 }),
                              H.Aura(25360, "Grace of Air") }
    H.Rescan(np)
    t.ok(H.Planned(np, "SCROLL:STAMINA") and not H.Find(np, "SCROLL:STAMINA"), "Stamina scroll up: tile waits invisibly")
    t.ok(H.Find(np, "SCROLL:AGILITY"), "Grace of Air totem up: Agility scroll still offered (they stack): " .. H.Keys(np))
    t.ok(H.Find(np, "SCROLL:PROTECTION"), "Protection still offered")

    -- Switches: + Scrolls off, or consumables off in groups
    local audit = np.env.BulwarkDB.audit
    t.eq(audit.checkScrolls, true, "scrolls on by default")
    audit.checkScrolls = false
    H.Rescan(np)
    t.ok(not H.Planned(np, "SCROLL:PROTECTION"), "+ Scrolls off: no scroll tiles")
    audit.checkScrolls = true
    audit.consumablesInGroup = false
    H.Rescan(np)
    t.ok(not H.Planned(np, "SCROLL:PROTECTION"), "consumables off in groups: no scroll tiles")

    -- Solo: follows the Solo checkbox; nobody gives Stamina solo
    local solo = t.fresh(function(s) H.Party(s); Bags(s); s.group = "none" end)
    H.Rescan(solo)
    t.ok(not H.Find(solo, "SCROLL:STAMINA"), "solo, defaults: no scroll tiles")
    solo.env.BulwarkDB.audit.consumablesSolo = true
    H.Rescan(solo)
    t.ok(H.Find(solo, "SCROLL:STAMINA"), "solo ticked: Stamina scroll offered: " .. H.Keys(solo))

    -- Paladin without a mage: Intellect scroll offered; other tiles keep their spell actions
    local p = t.fresh(function(s)
        s.units.player.class = "PALADIN"
        H.Party(s); Bags(s)
        s.items[STR_IV] = 1
        s.known[25780] = true
    end)
    H.Rescan(p)
    t.ok(H.Find(p, "SCROLL:INTELLECT"), "paladin, no mage: Intellect scroll offered: " .. H.Keys(p))
    t.ok(H.Find(p, "SCROLL:STRENGTH"), "paladin: Strength scroll offered")
    local rf = H.Find(p, "SELF:RIGHTEOUS_FURY")
    t.eq(rf:GetAttribute("type"), "spell", "self buff tile still casts")
    t.eq(rf:GetAttribute("item"), nil, "and has no item attribute")
end
