-- Mob abilities (Areas/Marking/Abilities.lua) over the generated Data/MobAbilities.lua (tools/gen-mob-abilities.ps1).
-- Ragefire Chasm (389) is checked against the 2026-11-15 in-game probe: Healing Wave 11986, Lightning Bolt 9532,
-- Shadow Bolt 20791 and Immolate 20800 are the spells the damage meter showed as interrupted.
local RFC = 389

return function(sim, t)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local A = MK.Abilities
    sim.spells[11986] = "Healing Wave"
    sim.spells[9532] = "Lightning Bolt"
    sim.spells[20791] = "Shadow Bolt"
    sim.spells[12746] = "Summon Voidwalker"

    -- Generated data: present and shaped as the generator documents.
    t.ok(type(MK.MobAbilities) == "table" and MK.MobAbilities[RFC], "RFC in the data")
    t.eq(MK.MobAbilityInstances[RFC], "Ragefire Chasm", "instance name")
    local shaman = MK.MobAbilities[RFC]["Ragefire Shaman"]
    t.ok(shaman and shaman.ids[1] == 11319 and shaman.cls == 2, "Ragefire Shaman entry (creature 11319, paladin class)")
    local function has(entry, id)
        for _, s in ipairs(A.Spells(entry)) do if s.id == id then return s end end
    end
    local hw = has(shaman, 11986)
    t.ok(hw and hw.kind == "heal" and hw.trigger == "allyhp" and hw.cast > 0, "Healing Wave: heal on a hurt ally, cast")
    t.ok(has(shaman, 9532), "Lightning Bolt")
    local warlock = MK.MobAbilities[RFC]["Searing Blade Warlock"]
    t.ok(has(warlock, 20791) and has(warlock, 20791).kind == "dmg", "Warlock: Shadow Bolt")
    t.eq(has(warlock, 12746).trigger, "ooc", "Warlock summons its Voidwalker out of combat")
    t.ok(MK.MobAbilities[RFC]["Jergosh the Invoker"].boss, "Jergosh flagged as encounter boss")
    t.ok(has(MK.MobAbilities[RFC]["Jergosh the Invoker"], 20800), "Jergosh: Immolate")

    -- Forever-only dungeons from Warcraft Logs runs: Ruins of Lordaeron (2999). No wiki data ships (dropped 2026-11-15).
    local ROL = 2999
    t.eq(MK.MobAbilityInstances[ROL], "Ruins of Lordaeron", "Forever-only instance named")
    local rath = MK.MobAbilities[ROL] and MK.MobAbilities[ROL]["Rath'mael"]
    t.ok(rath and rath.wcl and rath.boss and not rath.wiki, "Rath'mael: from the logs, boss")
    local fs = has(rath, 18399)
    t.ok(fs and fs.trigger == "wcl" and fs.cast > 0 and fs.kicked, "Flamestrike: from the logs, cast time from the game's data, interrupted")
    t.eq(A.Describe(fs):find("wcl", 1, true), nil, "no trigger text for wcl spells")
    sim.spells[18399] = "Flamestrike"
    sim:Slash("/bwk mark abilities Rath'mael")
    t.contains(sim.output, "Rath'mael %(Ruins of Lordaeron%)", "Forever mob found by name")
    for _, mobs in pairs(MK.MobAbilities) do
        for name, entry in pairs(mobs) do t.ok(not entry.wiki, "no wiki entries left: " .. name) end
    end

    -- Bosses scripted in the server's C++ code: spells their AI class uses (cmangos/mangos-classic).
    local doan = MK.MobAbilities[189] and MK.MobAbilities[189]["Arcanist Doan"]
    t.ok(doan, "Arcanist Doan (Scarlet Monastery) has data now")
    local poly = has(doan, 13323)
    t.ok(poly and poly.trigger == "script" and poly.kind == "cc", "Polymorph from his script, crowd control")
    t.ok(has(doan, 9433), "Arcane Explosion")
    t.eq(A.Describe(poly):find("script", 1, true), nil, "no trigger text for script spells")

    -- Every spell string in the whole file parses (catches a generator format change).
    local n = 0
    for _, mobs in pairs(MK.MobAbilities) do
        for name, entry in pairs(mobs) do
            t.ok(type(entry.ids) == "table" and #entry.ids > 0, "ids for " .. name)
            for _, s in ipairs(entry) do
                local p = A.ParseSpell(s)
                t.ok(p and p.id > 0 and p.kind ~= "" and p.trigger ~= "", "parses: " .. s)
                n = n + 1
            end
        end
    end
    t.ok(n > 1000, "over 1000 spells in the data (got " .. n .. ")")

    -- Parsing details: flags and the trailing argument.
    local p = A.ParseSpell("123;dot;0;hp;5;10;CA;30")
    t.ok(p.channel and p.area and p.arg == 30 and p.rmin == 5 and p.rmax == 10, "flags and arg parsed")
    t.ok(A.Interruptible(p), "channelled = interruptible")
    t.ok(not A.Interruptible(A.ParseSpell("1;dmg;0;combat;1;2;")), "instant = not interruptible")
    t.eq(A.ParseSpell("x;dmg"), nil, "garbage refused")
    local k = A.ParseSpell("20787;dmg;0;wcl;0;0;K")
    t.ok(k.kicked and not k.channel and A.Interruptible(k), "flag K: interrupted in Warcraft Logs runs = interruptible")
    t.ok(A.Describe(k):find("Warcraft Logs", 1, true) ~= nil, "K shown in the description")

    -- Lookup: case-insensitive; current instance first.
    local entry, real, where = A.Find("ragefire shaman", RFC)
    t.ok(entry == shaman and real == "Ragefire Shaman" and where == RFC, "found by lowercase name")
    t.eq(A.Find("Nobody Special"), nil, "unknown name")
    t.eq(A.Find(""), nil, "empty name")

    -- Description text.
    local text = A.Describe(hw)
    t.ok(text:find("^Healing Wave: heal, 3%.0 s cast, when an ally is hurt, every 24 s") ~= nil, "describe: " .. text)
    t.ok(text:find("interruptible") ~= nil, "Healing Wave marked interruptible")

    -- Command: by name (case kept), by target, nothing to go on, unknown mob.
    sim:Slash("/bwk mark abilities Ragefire Shaman")
    t.contains(sim.output, "Ragefire Shaman %(Ragefire Chasm%): 2 abilities", "header by name")
    t.contains(sim.output, "Healing Wave: heal", "Healing Wave line")
    sim.units.target = { name = "Searing Blade Warlock", friendly = false, level = 14 }
    sim:Slash("/bwk mark abilities")
    t.contains(sim.output, "Searing Blade Warlock %(Ragefire Chasm%)", "target used when no name given")
    t.contains(sim.output, "Summon Voidwalker: summon, instant, out of combat", "Voidwalker line")
    sim.units.target = nil
    sim:Slash("/bwk mark abilities")
    t.contains(sim.output, "Target a mob or give its name", "usage without target or name")
    sim:Slash("/bwk mark abilities Nobody Special")
    t.contains(sim.output, "No ability data for Nobody Special", "unknown mob: no data")

    -- Forever-only dungeons from Warcraft Logs runs (tools/export-wcl-abilities.ps1): Krol'dok Stronghold (3039).
    t.eq(MK.MobAbilityInstances[3039], "Krol'dok Stronghold", "Krol'dok has data")
    local ks = MK.MobAbilities[3039]["Krol'dok Shaman"]
    local bolt = ks and has(ks, 12167)
    t.ok(ks and ks.wcl and bolt and bolt.trigger == "wcl" and bolt.kicked, "Krol'dok Shaman: Lightning Bolt, interrupted in logs")
    t.ok(MK.MobAbilities[3039]["Overlord Mugg"].boss, "boss flag from the logs")
    sim:Slash("/bwk mark abilities Twilight Grunt")
    t.contains(sim.output, "Twilight Grunt %(Krol'dok Stronghold%)", "a Forever-only mob found")
end
