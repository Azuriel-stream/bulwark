-- Briefing: casts nobody can stop (flag U: an instant channel that stuns, fears or confuses everyone around it as it
-- starts). Maraudon (349): Landslide's Summon Shardlings 21808 = 100 yd stun for the whole 8 s channel [data]; the
-- user's group was stunned every time, about 1 min into the fight [in-game 2026-11-26]. No stunner is assigned to it:
-- from the data alone it is a "Can't interrupt:" heads-up; the curated hint makes it a note.
local H = require("mark_helpers")
local MARAUDON = 349

return function(_, t)
    local sim = t.fresh(function(s) H.install(s) end)
    local MK = sim.env.Bulwark.Marking
    local B, A = MK.Briefing, MK.Abilities
    sim.spells[21808] = "Summon Shardlings"
    sim.spells[11986] = "Healing Wave"
    sim.spells[72] = "Shield Bash"
    local P = A.ParseSpell
    local function knows(set) return function(ids) for _, id in ipairs(ids) do if set[id] then return true end end end end

    -- 1. Generated data and parsing.
    local entry = MK.MobAbilities[MARAUDON]["Landslide"]
    local shard
    for _, s in ipairs(A.Spells(entry)) do if s.id == 21808 then shard = s end end
    t.ok(shard and shard.unstoppable and shard.nokick and shard.channel and shard.cast == 0,
        "data: Summon Shardlings = instant channel, unstoppable")
    t.ok(not A.Kickable(shard), "not kickable")
    t.ok(A.Describe(shard):find("can't be stopped", 1, true) ~= nil, "description says it: " .. A.Describe(shard))
    t.ok(not P("1282071;cc;2000;wcl;0;0;AN").unstoppable, "a plain kick-proof cast isn't unstoppable")
    t.eq(B.DefaultPriority(shard), "must", "group stun = must (a heads-up)")

    -- 2. Data only (no hint): even a paladin's Hammer of Justice isn't given it.
    local tank = { short = "Tankard", tank = true, kit = B.KitFor("WARRIOR", 48, { known = knows({ [72] = true }), shield = true }) }
    local pally = { short = "Aldric", kit = B.KitFor("PALADIN", 48) }
    local palTank = { short = "Shieldy", tank = true, kit = B.KitFor("PALADIN", 48) }
    local function pack(lookup)
        return { { name = "Landslide", count = 1, boss = true, spells = B.MobSpells(entry, lookup) } }
    end
    local mobs = pack()
    local left = B.Assign(mobs, { tank, pally })
    local lines = B.BuildLines(mobs)
    t.eq(#mobs[1].assigned, 0, "nobody is assigned")
    t.eq(#left, 2, "tank and paladin stay free")
    t.eq(lines[1], "[Bulwark] Can't interrupt: Summon Shardlings (Landslide)", "heads-up line")
    t.eq(#lines, 1, "nothing else")

    mobs = pack()
    B.Assign(mobs, { palTank })
    t.eq(#mobs[1].assigned, 0, "a paladin tank doesn't take it either")

    -- A kick-proof must next to it still takes the stunner; the unstoppable one stays a heads-up.
    mobs = {
        { name = "Landslide", count = 1, boss = true, spells = B.MobSpells(entry) },
        { name = "Terrorhowl", count = 1, spells = B.MobSpells({ "1282071;cc;2000;wcl;0;0;AN" }) },
    }
    B.Assign(mobs, { tank, pally })
    t.ok(#mobs[1].assigned == 0 and mobs[2].assigned[1] == pally, "stun goes to the stoppable Howl")

    -- 3. With the curated hint: info, its note posted, no heads-up line.
    local hints = MK.BriefingHints[MARAUDON]["Landslide"]
    local hint = hints[21808]
    t.ok(hint and hint.note:find("Can't be stopped", 1, true) ~= nil, "hint in the data")
    mobs = pack(function(id) return hints[id] end)
    t.eq(mobs[1].spells[1].prio, "info", "hinted: info")
    B.Assign(mobs, { tank, pally })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Note: Summon Shardlings (Landslide): " .. hint.note, "note line posted")
    t.eq(#lines, 1, "only the note")
end
