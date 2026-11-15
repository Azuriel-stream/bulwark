-- Briefing step 1 (kb/addons/Bulwark-Briefing.md): priority engine + /bwk mark brief [preview].
-- Ragefire Chasm (389) data: Shaman = Healing Wave (heal, 3 s) + Lightning Bolt (dmg, 3 s); Warlock = Shadow Bolt
-- (dmg, 3 s) + Summon Voidwalker (out of combat); Trogg = Strike (instant).
local H = require("mark_helpers")
local RFC = 389

local function rfc(s)
    H.install(s)
    s.zone = "Ragefire Chasm"
    s.env.IsInInstance = function() return true, "party" end
    s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, RFC, 5, nil, false end
end

local function names(sim)
    sim.spells[11986] = "Healing Wave"
    sim.spells[9532] = "Lightning Bolt"
    sim.spells[20791] = "Shadow Bolt"
    sim.spells[12746] = "Summon Voidwalker"
    sim.spells[11976] = "Strike"
    sim.spells[20800] = "Immolate"
    sim.spells[3358] = "Leech Poison"
end

local function sent(sim, channel)
    local list = {}
    for _, c in ipairs(sim.chat) do
        if c.channel == channel then list[#list + 1] = c.msg end
    end
    return list
end

return function(_, t)
    local sim = t.fresh(rfc)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local B, A = MK.Briefing, MK.Abilities
    names(sim)
    local P = A.ParseSpell

    -- 1. Default priorities from the data.
    t.eq(B.DefaultPriority(P("11986;heal;3000;allyhp;24;24;")), "must", "cast heal = must")
    t.eq(B.DefaultPriority(P("113;cc;1500;combat;10;14;")), "must", "cast crowd control (Polymorph) = must")
    t.eq(B.DefaultPriority(P("9532;dmg;3000;combat;5;20;")), "should", "3 s damage cast = should")
    t.eq(B.DefaultPriority(P("1;dmg;0;combat;5;20;C")), "should", "channelled damage = should")
    t.eq(B.DefaultPriority(P("2;dmg;1500;combat;5;20;")), "ignore", "short damage cast = ignore")
    t.eq(B.DefaultPriority(P("11976;dmg;0;combat;6;12;")), "ignore", "instant = ignore")
    t.eq(B.DefaultPriority(P("8242;cc;0;combat;7;15;")), "ignore", "instant stun can't be kicked = ignore")
    t.eq(B.DefaultPriority(P("12746;summon;3000;ooc;0;0;")), "ignore", "cast before the pull = ignore")
    t.eq(B.DefaultPriority(P("3;heal;2000;spawn;0;0;")), "ignore", "spawn trigger = ignore")
    t.eq(B.DefaultPriority(P("4;passive;0;spawn;0;0;")), "ignore", "passive = ignore")
    t.eq(B.DefaultPriority(P("7121;buff;2000;combat;17;26;")), "should", "2 s buff cast (Anti-Magic Shield) = should")
    t.eq(B.DefaultPriority(P("18399;dmg;3000;wiki;0;0;A")), "should", "wiki spell with a cast = should")

    -- 2. Hints and the user's override.
    local strike = P("11976;dmg;0;combat;6;12;")
    local prio, source, note, deadly = B.Priority(strike, { flags = { "deadly" }, note = "Kills the healer." })
    t.ok(prio == "must" and source == "hint" and note == "Kills the healer." and deadly, "deadly hint = must")
    prio, source = B.Priority(strike, { flags = { interrupt = true } })
    t.ok(prio == "must" and source == "hint", "interrupt hint (set form) = must")
    prio, source, note = B.Priority(strike, { flags = { "dispel-poison" }, note = "Poisons the tank." })
    t.ok(prio == "info" and source == "hint" and note == "Poisons the tank.", "dispel hint = info with note")
    prio, source = B.Priority(strike, { flags = { "interrupt" } }, { prio = "ignore" })
    t.ok(prio == "ignore" and source == "user", "the user's override beats the hint")
    prio, source, note = B.Priority(P("11986;heal;3000;allyhp;24;24;"), nil, { prio = "should", note = "mine" })
    t.ok(prio == "should" and source == "user" and note == "mine", "override with note")
    prio = B.Priority(strike, nil, { prio = "bogus" })
    t.eq(prio, "ignore", "an invalid override falls back to the data")

    -- 3. One mob's list: best first, ignored counted, a spell under two triggers once.
    local shaman = MK.MobAbilities[RFC]["Ragefire Shaman"]
    local list, ignored = B.MobSpells(shaman)
    t.ok(#list == 2 and list[1].spell.id == 11986 and list[1].prio == "must"
        and list[2].spell.id == 9532 and list[2].prio == "should", "Shaman: Healing Wave must, Lightning Bolt should")
    t.eq(ignored, 0, "nothing ignored for the Shaman")
    list, ignored = B.MobSpells(MK.MobAbilities[RFC]["Searing Blade Warlock"])
    t.ok(#list == 1 and list[1].spell.id == 20791 and ignored == 1, "Warlock: Shadow Bolt; Voidwalker ignored")
    local sever = MK.MobAbilities[33] and MK.MobAbilities[33]["Sever"]
    list = B.MobSpells(sever)
    local n17745 = 0
    for _, item in ipairs(list) do if item.spell.id == 17745 then n17745 = n17745 + 1 end end
    t.eq(n17745, 1, "Sever: a spell listed under two triggers counts once")
    list = B.MobSpells(shaman, function(id) if id == 9532 then return nil, { prio = "must" } end end)
    t.ok(list[1].spell.id == 11986 and list[2].prio == "must" and list[2].source == "user",
        "lookup override applied; heal still first among musts")

    -- 4. Message lines.
    local lines = B.BuildLines({
        { name = "Ragefire Shaman", icon = 8, count = 1, spells = B.MobSpells(shaman) },
        { name = "Ragefire Shaman", count = 2, spells = B.MobSpells(shaman) },
        { name = "Searing Blade Warlock", count = 1, spells = B.MobSpells(MK.MobAbilities[RFC]["Searing Blade Warlock"]) },
        { name = "Ragefire Trogg", count = 3, spells = B.MobSpells(MK.MobAbilities[RFC]["Ragefire Trogg"]) },
    })
    t.eq(lines[1], "[Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave; 2x Ragefire Shaman: Healing Wave",
        "interrupt line")
    t.eq(lines[2], "[Bulwark] Best effort: Lightning Bolt, Shadow Bolt", "best-effort line, each spell once")
    t.eq(#lines, 2, "no note line without notes; the Trogg adds nothing")
    lines = B.BuildLines({ { name = "Witherfang", count = 1, spells = B.MobSpells({ "3358;dot;0;wiki;0;0;" },
        function() return { flags = { "dispel-poison" }, note = "Poisons the tank|healer." } end) } })
    t.eq(lines[1], "[Bulwark] Note: Leech Poison (Witherfang): Poisons the tank/healer.", "note line, no bare pipe")
    t.eq(#B.BuildLines({ { name = "Ragefire Trogg", count = 1, spells = {} } }), 0, "nothing to say: no lines")
    local many = {}
    for i = 1, 12 do many[i] = { name = "Ragefire Shaman", icon = (i % 8) + 1, count = 1, spells = B.MobSpells(shaman) } end
    for _, l in ipairs(B.BuildLines(many)) do t.ok(#l <= 250, "wrapped line fits a chat message (" .. #l .. ")") end

    -- 5. In the dungeon with readable names: the pack in view + a far target; marks from Marking.
    H.pack(sim)   -- nameplate1 Trogg, nameplate2 Shaman, nameplate3 Trogg
    sim.units.nameplate4 = { name = "Searing Blade Warlock", friendly = false, level = 14, tier = "elite", power = "MANA" }
    sim.units.nameplate5 = { name = "Ragefire Shaman", friendly = false, level = 13, tier = "elite", power = "MANA" }
    sim.units.nameplate6 = { name = "Jergosh the Invoker", friendly = false, level = 16, tier = "elite",
                             power = "MANA", far = true }
    sim.units.nameplate7 = { name = "Some Forever Mob", friendly = false, level = 15, tier = "elite", power = "RAGE" }
    for i = 1, 7 do sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    sim:Advance(1)
    t.eq(MK.Plates.instanceID, RFC, "instance known")
    env.SetRaidTarget("nameplate2", 8)
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    local mobs, summary = B.Collect()
    t.eq(summary.total, 6, "six near plates (Jergosh is far and not targeted)")
    t.eq(summary.noData["Some Forever Mob"], 1, "mob without data counted")
    t.ok(mobs[1].name == "Ragefire Shaman" and mobs[1].icon == 8, "skull first")
    sim.output = {}
    sim:Slash("/bwk mark brief preview")
    t.contains(sim.output, "Briefing preview: 6 mobs", "preview header")
    t.contains(sim.output, "2x Ragefire Trogg: nothing to interrupt", "unmarked Troggs merged")
    t.contains(sim.output, "No ability data: Some Forever Mob", "no-data mob listed")
    t.contains(sim.output, "Would post:", "would-post section")
    t.contains(sim.output, "Best effort: Lightning Bolt, Shadow Bolt", "best effort in the preview")
    t.eq(#sent(sim, "PARTY"), 0, "preview sends nothing")

    sim.units.target = sim.units.nameplate6
    sim:Fire("PLAYER_TARGET_CHANGED")
    sim:Advance(1)
    sim:Slash("/bwk mark brief")
    local party = sent(sim, "PARTY")
    t.eq(party[1], "[Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave; Ragefire Shaman: Healing Wave",
        "posted interrupt line")
    t.eq(party[2], "[Bulwark] Best effort: Lightning Bolt, Shadow Bolt, Immolate", "the far boss target is included")
    t.eq(#party, 2, "two lines posted")

    -- Not in combat; not while addon chat is restricted; solo prints instead.
    sim:EnterCombat()
    sim.output = {}
    sim:Slash("/bwk mark brief")
    t.contains(sim.output, "not in combat", "refused in combat")
    sim:LeaveCombat()
    sim:Fire("PLAYER_REGEN_ENABLED")
    sim:Advance(1)
    t.eq(#sent(sim, "PARTY"), 2, "nothing posted in combat")
    sim.group = "none"
    sim.output = {}
    sim:Slash("/bwk mark brief")
    t.contains(sim.output, "Not in a group", "solo: printed instead")
    sim.group = "party"
    t.eq(#sent(sim, "PARTY"), 2, "nothing posted solo")

    -- Nothing worth a kick.
    for i = 2, 7 do sim.units["nameplate" .. i] = nil; sim:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
    sim.units.target = nil
    sim:Fire("PLAYER_TARGET_CHANGED")
    sim:Advance(1)
    sim.output = {}
    sim:Slash("/bwk mark brief")
    t.contains(sim.output, "Nothing to brief", "only a Trogg left: nothing posted")
    t.eq(#sent(sim, "PARTY"), 2, "still two lines")

    -- 6. Names secret (dungeon): nameless plates are counted, never guessed; a learned name (%t echo) is used.
    local sim2 = t.fresh(rfc)
    names(sim2)
    local MK2 = sim2.env.Bulwark.Marking
    sim2.restricted = true
    sim2.units.nameplate1 = { name = "Ragefire Shaman", friendly = false, level = 13, tier = "elite", power = "MANA" }
    sim2.units.nameplate2 = { name = "Ragefire Shaman", friendly = false, level = 13, tier = "elite", power = "MANA" }
    sim2:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    sim2:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    sim2:Advance(1)
    local _, s2 = MK2.Briefing.Collect()
    t.eq(s2.unknown, 2, "two nameless plates")
    sim2.units.target = sim2.units.nameplate1
    sim2:Fire("PLAYER_TARGET_CHANGED")
    sim2:Advance(1)
    local n = tonumber(sim2.chat[#sim2.chat].msg:match("^BWK~(%d+)~"))
    sim2:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~" .. n .. "~Ragefire Shaman", "Tankard Stoneforge")
    sim2:Advance(1)
    local mobs2, s3 = MK2.Briefing.Collect()
    t.ok(#mobs2 == 1 and mobs2[1].name == "Ragefire Shaman" and s3.unknown == 1, "learned name used, the other unknown")
    sim2.output = {}
    sim2:Slash("/bwk mark brief preview")
    t.contains(sim2.output, "1 mobs not identified", "preview tells you to Tab-target the rest")
    t.eq(#sim2.errors, 0, "no Lua errors with secret names")

    -- Help line and the singular ability count.
    sim:Slash("/bwk mark help")
    t.contains(sim.output, "/bwk mark brief", "help lists the command")
    sim:Slash("/bwk mark abilities Oggleflint")
    t.contains(sim.output, "Oggleflint %(Ragefire Chasm%): 1 ability$", "singular: 1 ability")
    t.eq(#sim.errors, 0, "no Lua errors")
end
