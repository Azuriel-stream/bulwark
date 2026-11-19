-- Briefing: casts kicks can't stop (flag N, from the game's SpellCategories data; kb references.md §5f).
-- A must one goes to a stunner, else a "Can't interrupt:" heads-up line; a should one is dropped (nobody can kick it).
-- Krol'dok Stronghold (3039): Terrorhowl's Frightening Howl (2 s fear, 60 yd, N) and War Handler Ashka's
-- Command: Kill! hint (user 2026-11-19).
local H = require("mark_helpers")
local KROLDOK = 3039

return function(_, t)
    local sim = t.fresh(function(s) H.install(s) end)
    local MK = sim.env.Bulwark.Marking
    local B, A = MK.Briefing, MK.Abilities
    sim.spells[1282071] = "Frightening Howl"
    sim.spells[1282076] = "Command: Kill!"
    sim.spells[11986] = "Healing Wave"
    sim.spells[9532] = "Lightning Bolt"
    sim.spells[72] = "Shield Bash"
    local P = A.ParseSpell
    local function knows(set) return function(ids) for _, id in ipairs(ids) do if set[id] then return true end end end end

    -- 1. Generated data and parsing.
    local howlEntry = MK.MobAbilities[KROLDOK]["Terrorhowl"]
    local howl = A.Spells(howlEntry)[1]
    t.ok(howl.id == 1282071 and howl.nokick and howl.area and howl.cast == 2000, "data: Frightening Howl = 2 s, area, no kick")
    t.ok(A.Interruptible(howl) and not A.Kickable(howl), "a stun stops it, a kick doesn't")
    t.ok(A.Describe(howl):find("can't be kicked", 1, true) ~= nil, "description says it: " .. A.Describe(howl))
    t.ok(not P("11986;heal;3000;allyhp;24;24;K").nokick, "K (interrupted in logs) has no N")

    -- 2. Priorities: crowd control / heal stay must; anything else that can't be kicked is dropped.
    t.eq(B.DefaultPriority(howl), "must", "kick-proof crowd control = must")
    t.eq(B.DefaultPriority(P("7106;heal;2000;allyhp;22;34;N")), "must", "kick-proof heal = must")
    t.eq(B.DefaultPriority(P("20904;dmg;2000;combat;5;9;N")), "ignore", "kick-proof damage cast (Aimed Shot) = ignore")
    t.eq(B.DefaultPriority(P("9532;dmg;3000;combat;5;20;")), "should", "a normal 3 s damage cast is still should")

    -- 3. Assignment: a warrior tank can't take it; a stunner can.
    local tank = { short = "Tankard", tank = true, kit = B.KitFor("WARRIOR", 43, { known = knows({ [72] = true }), shield = true }) }
    local rogue = { short = "Vex", kit = B.KitFor("ROGUE", 43) }
    local pally = { short = "Aldric", kit = B.KitFor("PALADIN", 43) }
    local function pack()
        return { { name = "Terrorhowl", count = 1, spells = B.MobSpells(howlEntry) } }
    end

    local mobs = pack()
    local left = B.Assign(mobs, { tank, rogue })
    local lines = B.BuildLines(mobs)
    t.eq(#mobs[1].assigned, 0, "no kicker is given the Howl")
    t.eq(lines[1], "[Bulwark] Can't interrupt: Frightening Howl (Terrorhowl)", "heads-up line instead")
    t.eq(#lines, 1, "no Interrupt / Best effort line for it")
    t.eq(#left, 2, "tank and rogue stay free")

    mobs = pack()
    B.Assign(mobs, { tank, rogue, pally })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Interrupt: Terrorhowl: Frightening Howl -> Aldric (Hammer of Justice)", "the stunner takes it")
    t.eq(#lines, 1, "covered: no heads-up line")

    -- A paladin tank stuns it themselves.
    local palTank = { short = "Shieldy", tank = true, kit = B.KitFor("PALADIN", 43) }
    mobs = pack()
    B.Assign(mobs, { palTank })
    t.eq(B.BuildLines(mobs)[1], "[Bulwark] Interrupt: Terrorhowl: Frightening Howl -> Shieldy (Hammer of Justice)",
        "paladin tank: Hammer of Justice")

    -- Stunners go to the kick-proof mob first; kickers keep the heal.
    local shaman = { "11986;heal;3000;allyhp;24;24;", "9532;dmg;3000;combat;5;20;" }
    mobs = {
        { name = "Ragefire Shaman", icon = 8, count = 1, spells = B.MobSpells(shaman) },
        { name = "Terrorhowl", count = 1, spells = B.MobSpells(howlEntry) },
    }
    B.Assign(mobs, { tank, pally, rogue })
    t.ok(mobs[1].assigned[1] == tank and mobs[2].assigned[1] == pally, "tank on the heal, stun on the Howl")
    t.eq(#mobs[1].assigned, 1, "the rogue isn't needed")

    -- A mob with a kickable and a kick-proof must: the kicker covers the kickable one, the other is a heads-up.
    mobs = { { name = "Twin Caster", count = 1, spells = B.MobSpells({ "11986;heal;3000;allyhp;24;24;", "1282071;cc;2000;wcl;0;0;AN" }) } }
    B.Assign(mobs, { tank })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Interrupt: Twin Caster: Healing Wave -> Tankard (Shield Bash)", "kicker covers the heal only")
    t.eq(lines[2], "[Bulwark] Can't interrupt: Frightening Howl (Twin Caster)", "the Howl is a heads-up")

    -- 4. War Handler Ashka: Command: Kill! as a tank hint (info, note posted).
    local ashka = MK.MobAbilities[KROLDOK]["War Handler Ashka"]
    local hint = MK.BriefingHints[KROLDOK]["War Handler Ashka"][1282076]
    t.ok(hint and hint.note:find("taunt them back", 1, true) ~= nil, "hint in the data")
    local list = B.MobSpells(ashka, function(id) return MK.BriefingHints[KROLDOK]["War Handler Ashka"][id] end)
    t.ok(#list == 1 and list[1].spell.id == 1282076 and list[1].prio == "info", "only Command: Kill! listed, as info")
    mobs = { { name = "War Handler Ashka", count = 1, boss = true, spells = list } }
    B.Assign(mobs, { tank })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Note: Command: Kill! (War Handler Ashka): " .. hint.note, "note line posted")
end
