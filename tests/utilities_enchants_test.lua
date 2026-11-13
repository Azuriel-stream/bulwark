-- Gear audit, step 1: generated enchant data (tools/gen-enchants.ps1) + ranking by avoidance gain.
-- Values [data]: wago.tools wowf 1.60.1.70888 (kb/addons/Bulwark-Utilities.md "Idea: Gear audit").
return function(sim, t)
    local NS = sim.env.Bulwark
    local E, data = NS.Enchants, NS.EnchantData
    local function near(a, b, msg)
        t.ok(type(a) == "number" and math.abs(a - b) < 0.001, (msg or "number") .. ": expected " .. b .. ", got " .. tostring(a))
    end
    -- Level 60 warrior with a shield (same as utilities_test.lua); 12 dodge from 240 agility = 0.05 % per point.
    local function snap(over)
        local s = { level = 60, defense = 400, dodge = 12, parry = 11, block = 14, hasShield = true,
                    known = {}, active = {}, dodgePerAgi = 0.05 }
        for k, v in pairs(over or {}) do s[k] = v end
        return s
    end
    local WRIST, BACK, OFFHAND, MAINHAND, HEAD = 9, 15, 17, 16, 1
    local armor = { classID = 4, subClassID = 4, equipLoc = "INVTYPE_WRIST", ilvl = 60 }
    local shield = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD", ilvl = 60 }
    local oneHand = { classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON", ilvl = 60 }
    local twoHand = { classID = 2, subClassID = 8, equipLoc = "INVTYPE_2HWEAPON", ilvl = 60 }

    -- Data sanity
    t.ok(data and data.stats and data.sources and #data.sources > 100, "generated data loaded")
    t.eq(data.stats[923].def, 7, "Bracer - Deflection = Defense +7")
    t.eq(data.stats[8214].def, 9, "Bracer - Superior Deflection (Forever) = Defense +9")
    t.eq(data.stats[2622].dodge, 1, "Cloak - Dodge = 1 %")
    t.eq(data.stats[2583].def, 7, "Presence of Might: Defense +7")
    local origins, sod = {}, false
    for _, src in ipairs(data.sources) do
        origins[src.origin] = true
        if src.spell == 1219587 then sod = true end         -- SoD Cloak - Agility: left out
        t.ok(src.reagents or src.item, "source " .. src.spell .. " has mats or an item")
    end
    t.ok(origins.vanilla and origins.forever and not origins.sod and not sod, "origins: vanilla + forever, no SoD")

    -- Spell power enchants [data 70938]: kept for Paladins (threat stat), offered to nobody else.
    t.eq(data.stats[8218].sp, 6, "Necklace - Spell Power = +6")
    t.ok(data.stats[8218].caster and data.stats[8492].caster, "spell power enchants are caster-only")
    t.eq(data.stats[8492].armor, 40, "Mystic Rugged Armor Kit keeps its armor")
    t.eq(data.stats[2504].sp, 30, "Weapon - Spell Power = +30 (Holy-school damage aura)")
    t.ok(data.stats[8217].proc and data.stats[8217].caster, "Weapon - Revelation: caster proc")
    t.ok(data.stats[8216] == nil, "Weapon - Insight (Spirit) stays out")
    do
        local NECK = 2
        local neck = { classID = 4, subClassID = 0, equipLoc = "INVTYPE_NECK", ilvl = 60 }
        local function has(list, id) for _, e in ipairs(list) do if e.enchant == id then return e end end end
        local NS = sim.env.Bulwark
        local before = NS.playerClass
        NS.playerClass = "WARRIOR"
        local warNeck = E.ForSlot(snap(), NECK, neck, nil)
        t.ok(#warNeck > 0 and not has(warNeck, 8218), "Warrior: neck enchants, but no spell power necklace")
        NS.playerClass = "PALADIN"
        local list = E.ForSlot(snap(), NECK, neck, nil)
        local sp = has(list, 8218)
        t.ok(sp and sp.sp == 6, "Paladin: spell power necklace offered with its spell power")
        local spPos, zeroPos
        for i, e in ipairs(list) do
            if e.enchant == 8218 then spPos = i end
            if math.abs(e.gain) < 0.005 and e.stamina == 0 and e.sp == 0 and not zeroPos then zeroPos = i end
        end
        t.ok(not zeroPos or spPos < zeroPos, "spell power breaks the tie before enchants that add nothing")
        NS.playerClass = before
    end

    -- Link parsing
    t.eq(E.FromLink("|cffffffff|Hitem:12345:923:::::::60|h[x]|h|r"), 923, "enchant from link")
    t.eq(E.FromLink("|cffffffff|Hitem:12345::::::::60|h[x]|h|r"), nil, "no enchant")
    t.eq(E.FromLink(nil), nil, "no link")

    -- Gain: 7 defense = 0.04 % x 7 on each of miss, dodge, parry, block = 1.12 %
    local s = snap()
    local gain, sta = E.Gain(s, 923, nil, { offset = 3 })
    near(gain, 1.12, "Deflection on a bare bracer"); t.eq(sta, 0, "no stamina")
    gain = E.Gain(s, 8214, 923, { offset = 3 })
    near(gain, 0.32, "Superior Deflection over Deflection: 2 more defense")
    gain, sta = E.Gain(s, 929, 923, { offset = 3 })
    near(gain, -1.12, "Greater Stamina over Deflection loses the defense"); t.eq(sta, 7, "but gains 7 stamina")
    near(E.Gain(s, 2622, nil, { offset = 3 }), 1, "Cloak - Dodge: 1 %")
    near(E.Gain(s, 863, nil, { offset = 3 }), 2, "Shield - Lesser Block: 2 % with a shield")
    near(E.Gain(snap({ hasShield = false }), 863, nil, { offset = 3 }), 0, "no shield: block counts for nothing")

    -- Warrior with Shield Block: block chance doesn't count (Shield Block fills the table on cooldown)
    local war = snap({ known = { shieldBlock = true } })
    t.ok(E.IgnoresBlock(war), "Warrior with Shield Block and a shield ignores block")
    t.ok(not E.IgnoresBlock(snap({ known = { shieldBlock = true }, hasShield = false })), "no shield: rule off")
    t.ok(not E.IgnoresBlock(snap({ known = { holyShield = true } })), "Paladin keeps block")
    t.ok(not E.IgnoresBlock(nil), "no snapshot")
    near(E.Gain(war, 863, nil, { offset = 3 }), 0, "Warrior: Shield - Lesser Block adds nothing")
    near(E.Gain(war, 923, nil, { offset = 3 }), 0.84, "Warrior: Deflection = miss, dodge, parry only (7 x 0.12)")
    near(E.Gain(war, 2622, nil, { offset = 3 }), 1, "Warrior: Cloak - Dodge unchanged")
    near(E.Gain(snap({ known = { shieldBlock = true }, active = { shieldBlock = true }, block = 89 }), 863, nil,
        { offset = 3 }), 0, "Warrior with Shield Block up: still nothing")
    local sh = E.ForSlot(war, OFFHAND, shield, nil, { offset = 3 })
    t.ok(sh[1].enchant ~= 863 and sh[1].stamina > 0, "Warrior shield: a stamina enchant ranks above Lesser Block")
    t.eq((E.ForSlot(s, OFFHAND, shield, nil, { offset = 3 }))[1].enchant, 863, "Paladin/no Shield Block: Lesser Block first")

    -- Ranking: wrist, best first; stamina breaks ties among zero-avoidance enchants
    local list = E.ForSlot(s, WRIST, armor, nil, { offset = 3 })
    t.eq(list[1].enchant, 8214, "wrist: Superior Deflection first")
    t.eq(list[2].enchant, 923, "then Deflection")
    local firstZero
    for i, e in ipairs(list) do
        if e.gain <= 0.005 then firstZero = firstZero or i end
    end
    t.ok(firstZero and list[firstZero].stamina >= 9, "first zero-avoidance wrist enchant is the best stamina one")

    -- Verdicts
    t.eq((E.Verdict(s, WRIST, armor, nil, { offset = 3 })), "missing", "bare bracer: missing")
    t.eq((E.Verdict(s, WRIST, armor, 929, { offset = 3 })), "weaker", "Greater Stamina bracer: weaker")
    t.eq((E.Verdict(s, WRIST, armor, 8214, { offset = 3 })), nil, "Superior Deflection: fine")

    -- Item requirements
    local function has(l, id)
        for _, e in ipairs(l) do if e.enchant == id then return true end end
        return false
    end
    t.ok(has(E.ForSlot(s, OFFHAND, shield, nil), 863), "shield enchants fit a shield")
    t.eq(#E.ForSlot(s, OFFHAND, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE", ilvl = 60 }, nil), 0,
        "no tank enchants for a held-in-off-hand item")
    t.ok(has(E.ForSlot(s, MAINHAND, twoHand, nil), 2646), "2H Agility fits a two-hander")
    t.ok(not has(E.ForSlot(s, MAINHAND, oneHand, nil), 2646), "2H Agility does not fit a one-hander")
    t.ok(has(E.ForSlot(s, MAINHAND, oneHand, nil), 2564), "Weapon - Agility fits a one-hander")
    t.ok(has(E.ForSlot(s, HEAD, { classID = 4, subClassID = 4, equipLoc = "INVTYPE_HEAD", ilvl = 60 }, nil), 2583),
        "Presence of Might at level 60")
    t.ok(not has(E.ForSlot(snap({ level = 50 }), HEAD, { classID = 4, subClassID = 4, equipLoc = "INVTYPE_HEAD", ilvl = 60 }, nil), 2583),
        "Presence of Might needs level 60")
    t.ok(not has(E.ForSlot(s, BACK, { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK", ilvl = 60 }, nil), 2564),
        "weapon enchants don't fit a cloak")

    -- Item level: Heavy Armor Kit (8484) is "only usable on items level 15 and above" [data] (ItemLevelMin = $ecim)
    local function gloves(ilvl) return { classID = 4, subClassID = 3, equipLoc = "INVTYPE_HAND", ilvl = ilvl } end
    t.ok(not has(E.ForSlot(s, 10, gloves(14), nil), 8484), "Heavy Armor Kit: not on an item level 14 item")
    t.ok(has(E.ForSlot(s, 10, gloves(15), nil), 8484), "Heavy Armor Kit: item level 15 is enough")
    t.ok(not has(E.ForSlot(s, 10, gloves(nil), nil), 8484), "item level unknown (not cached yet): kits left out")
    t.ok(has(E.ForSlot(s, 10, gloves(5), nil), 1887), "enchanting recipes have no item level floor")
end
