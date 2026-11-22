-- Briefing: a shaman's Tremor Totem (8143, level 18) breaks fear, charm and sleep (flag F, from the game's spell data:
-- fear/charm aura with that mechanic, stun aura + sleep). With a shaman in the group those casts get no interrupter
-- and a "Tremor Totem -> <shaman>:" line instead (user 2026-11-20). Terrorhowl's Frightening Howl (Krol'dok
-- Stronghold 3039) and Durgen Dirgehammer's instant Intimidating Shout (Hall of Thanes 3065) from the real data.
local H = require("mark_helpers")
local KROLDOK, THANES = 3039, 3065

return function(_, t)
    local sim = t.fresh(function(s) H.install(s) end)
    local MK = sim.env.Bulwark.Marking
    local B, A = MK.Briefing, MK.Abilities
    sim.spells[1282071] = "Frightening Howl"
    sim.spells[19134] = "Intimidating Shout"
    sim.spells[11986] = "Healing Wave"
    sim.spells[6215] = "Fear"
    sim.spells[72] = "Shield Bash"
    sim.spells[8042] = "Earth Shock"
    local P = A.ParseSpell
    local function knows(set) return function(ids) for _, id in ipairs(ids) do if set[id] then return true end end end end

    -- 1. Data and parsing.
    local howlEntry = MK.MobAbilities[KROLDOK]["Terrorhowl"]
    local howl = A.Spells(howlEntry)[1]
    t.ok(howl.id == 1282071 and howl.tremor and howl.nokick, "data: Frightening Howl = fear (F), no kick")
    t.ok(A.Describe(howl):find("Tremor Totem breaks it", 1, true) ~= nil, "description says it: " .. A.Describe(howl))
    t.ok(not P("11986;heal;3000;allyhp;24;24;").tremor, "no F, no tremor")
    local durgen = MK.MobAbilities[THANES]["Durgen Dirgehammer"]
    local shout
    for _, s in ipairs(A.Spells(durgen)) do if s.id == 19134 then shout = s end end
    t.ok(shout and shout.tremor and shout.cast == 0, "data: Intimidating Shout = instant fear (F)")

    -- 2. Priorities: an instant fear is info (nothing to kick); a cast fear stays must.
    t.eq(B.DefaultPriority(shout), "info", "instant fear = info")
    t.eq(B.DefaultPriority(P("7399;cc;0;combat;10;20;")), "ignore", "instant crowd control without F = ignore (as before)")
    t.eq(B.DefaultPriority(P("6215;cc;1500;combat;10;20;F")), "must", "a cast fear = must")

    -- 3. Who drops it: shamans from level 18; you by your spellbook.
    t.ok(B.HasTremor("SHAMAN", 18) and not B.HasTremor("SHAMAN", 17), "shaman: level 18")
    t.ok(not B.HasTremor("WARRIOR", 60), "warriors don't")
    t.ok(B.HasTremor("SHAMAN", 10, { known = knows({ [8143] = true }) }), "you: if you know it")
    t.ok(not B.HasTremor("SHAMAN", 60, { known = knows({}) }), "you: not if you don't")

    local tank = { short = "Tankard", tank = true, kit = B.KitFor("WARRIOR", 43, { known = knows({ [72] = true }), shield = true }) }
    local rogue = { short = "Vex", kit = B.KitFor("ROGUE", 43) }
    local pally = { short = "Aldric", kit = B.KitFor("PALADIN", 43) }
    local sham = { short = "Rainclaw", level = 43, kit = B.KitFor("SHAMAN", 43), tremor = B.HasTremor("SHAMAN", 43) }
    local function pack()
        return { { name = "Terrorhowl", count = 1, spells = B.MobSpells(howlEntry) } }
    end

    -- 4. Frightening Howl: without a shaman the old behaviour (stunner, else heads-up); with one, the totem.
    local mobs = pack()
    B.Assign(mobs, { tank, rogue })
    t.eq(B.BuildLines(mobs)[1], "[Bulwark] Can't interrupt: Frightening Howl (Terrorhowl)", "no shaman: heads-up")

    mobs = pack()
    local left = B.Assign(mobs, { tank, rogue, pally, sham })
    local lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Tremor Totem -> Rainclaw: Frightening Howl (Terrorhowl)", "shaman: Tremor Totem line")
    t.eq(#lines, 1, "no Interrupt / Can't interrupt line for it")
    t.eq(#mobs[1].assigned, 0, "the paladin's stun isn't spent on it")
    t.eq(#left, 4, "everyone stays free (the shaman can still interrupt)")
    t.ok(B.Worth(mobs), "worth a tile")

    -- 5. A cast fear on a caster next to a heal: the totem takes the fear, the kicker the heal; no best effort for Fear.
    local caster = { "11986;heal;3000;allyhp;24;24;", "6215;cc;1500;combat;10;20;F" }
    mobs = { { name = "Dark Caster", icon = 8, count = 1, spells = B.MobSpells(caster) } }
    B.Assign(mobs, { tank, sham })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Interrupt: {rt8} Dark Caster: Healing Wave -> Tankard (Shield Bash)", "tank on the heal")
    t.eq(lines[2], "[Bulwark] Tremor Totem -> Rainclaw: Fear (Dark Caster)", "totem on the fear")
    t.eq(#lines, 2, "nothing else")

    -- Without a shaman the fear is a must like before (kicker on the top must: Healing Wave covers both names).
    mobs = { { name = "Dark Caster", icon = 8, count = 1, spells = B.MobSpells(caster) } }
    B.Assign(mobs, { tank })
    t.eq(B.BuildLines(mobs)[1], "[Bulwark] Interrupt: {rt8} Dark Caster: Healing Wave, Fear -> Tankard (Shield Bash)",
        "no shaman: the kicker watches both")

    -- 6. Durgen's instant Intimidating Shout (hint: important, note): totem line + the hint's note.
    local hints = MK.BriefingHints[THANES]["Durgen Dirgehammer"]
    local list = B.MobSpells(durgen, function(id) return hints[id] end)
    mobs = { { name = "Durgen Dirgehammer", count = 1, boss = true, spells = list } }
    B.Assign(mobs, { tank, sham })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Tremor Totem -> Rainclaw: Intimidating Shout (Durgen Dirgehammer)", "instant fear: totem")
    t.eq(lines[#lines], "[Bulwark] Note: Intimidating Shout (Durgen Dirgehammer): Fears at low health.", "note still posted")

    -- An instant fear on trash: no tile without a shaman, a tile with one.
    local trash = { "19134;cc;0;combat;10;20;AF" }
    mobs = { { name = "Shouter", count = 1, spells = B.MobSpells(trash) } }
    B.Assign(mobs, { tank })
    t.ok(not B.Worth(mobs) and #B.BuildLines(mobs) == 0, "no shaman: nothing to brief")
    mobs = { { name = "Shouter", count = 1, spells = B.MobSpells(trash) } }
    B.Assign(mobs, { tank, sham })
    t.ok(B.Worth(mobs), "shaman: worth a tile")
    t.eq(B.BuildLines(mobs)[1], "[Bulwark] Tremor Totem -> Rainclaw: Intimidating Shout (Shouter)", "shaman: totem line")

    -- 7. Two shamans: the higher level drops it; a user "ignore" on the fear keeps it out.
    local low = { short = "Aaron", level = 30, kit = B.KitFor("SHAMAN", 30), tremor = true }
    mobs = pack()
    B.Assign(mobs, { tank, low, sham })
    t.eq(B.BuildLines(mobs)[1], "[Bulwark] Tremor Totem -> Rainclaw: Frightening Howl (Terrorhowl)", "highest level shaman")
    list = B.MobSpells(howlEntry, function() return nil, { prio = "ignore" } end)
    mobs = { { name = "Terrorhowl", count = 1, spells = list } }
    B.Assign(mobs, { tank, sham })
    t.eq(#B.BuildLines(mobs), 0, "ignored by you: never mentioned")
end
