-- Briefing step 5 (kb/addons/Bulwark-Briefing.md): casts seen in play, from the damage meter after each fight.
-- DamageTaken rows name the enemy; Interrupts rows only give the stopped spell, pinned to a mob when the pull allows.
local H = require("mark_helpers")
local RFC = 389
local GUID_ME, GUID_LUMEN = "Player-1-00000001", "Player-1-00000002"

return function(_, t)
    local enemies, spells = {}, {}   -- meter content of the fight that just ended
    local sim = t.fresh(function(s)
        H.install(s)
        s.zone = "Ragefire Chasm"
        s.env.IsInInstance = function() return true, "party" end
        s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, RFC, 5, nil, false end
        s.env.C_DamageMeter = {
            GetCombatSessionFromType = function(_, meterType)
                if s.inCombat then error("secret in combat") end
                return { combatSources = meterType == 10 and enemies or {} }
            end,
            GetCombatSessionSourceFromType = function(_, meterType, guid)
                if s.inCombat then error("secret in combat") end
                return { combatSpells = (spells[meterType] or {})[guid] or {} }
            end,
        }
    end)
    local env = sim.env
    env.Enum.DamageMeterSessionType = env.Enum.DamageMeterSessionType or { Overall = 0, Current = 1 }
    env.Enum.DamageMeterType = env.Enum.DamageMeterType or { Interrupts = 5, DamageTaken = 7, EnemyDamageTaken = 10 }
    local MK = env.Bulwark.Marking
    local B = MK.Briefing
    sim.spells[9532], sim.spells[11986], sim.spells[20791] = "Lightning Bolt", "Healing Wave", "Shadow Bolt"
    sim.spells[99001], sim.spells[99002] = "Mystery Mend", "Puzzling Bolt"
    sim.spells[99003], sim.spells[99004] = "Grunt Smash", "Shadow Hex"

    local function hit(id, mob) return { spellID = id, combatSpellDetails = { unitName = mob, isMob = true } } end
    local function kick(id) return { spellID = id, combatSpellDetails = { unitName = "", isMob = false } } end
    local function fight()
        sim:EnterCombat()
        sim:Fire("PLAYER_REGEN_DISABLED")
        sim:LeaveCombat()
        sim:Fire("PLAYER_REGEN_ENABLED")
        sim:Advance(3)
    end
    local function rec(inst, mob, id)
        local m = B.LearnedMobs(inst)[mob]
        return m and m[id]
    end

    -- 1. RFC: Shaman + Trogg. I take Lightning Bolt (known) and Strike, I kick Healing Wave (known, Shaman's);
    --    Lumen kicks an unknown spell: the Shaman is the only caster in the pull.
    enemies = { { name = "Ragefire Shaman", classFilename = "PALADIN", classification = "elite" },
                { name = "Ragefire Trogg", classFilename = "WARRIOR", classification = "elite" },
                { name = "Tankard", isLocalPlayer = true, classFilename = "WARRIOR" } }
    spells = {
        [7] = { [GUID_ME] = { hit(9532, "Ragefire Shaman"), hit(11976, "Ragefire Trogg"), hit(6603, "Ragefire Trogg") } },
        [5] = { [GUID_ME] = { kick(11986) }, [GUID_LUMEN] = { kick(99001) } },
    }
    fight()
    t.ok(rec(RFC, "Ragefire Shaman", 9532) and rec(RFC, "Ragefire Shaman", 9532).how == "hit", "Lightning Bolt seen (hit)")
    t.ok(rec(RFC, "Ragefire Trogg", 11976), "Strike seen")
    t.eq(rec(RFC, "Ragefire Trogg", 6603), nil, "melee swings not recorded")
    t.ok(rec(RFC, "Ragefire Shaman", 11986) and rec(RFC, "Ragefire Shaman", 11986).how == "kick",
        "kicked Healing Wave pinned to the Shaman (the only mob that casts it)")
    t.ok(rec(RFC, "Ragefire Shaman", 99001), "unknown kicked spell pinned to the only caster in the pull")
    local entry = B.FindEntry("Ragefire Shaman", RFC)
    local new
    for _, s in ipairs(MK.Abilities.Spells(entry)) do if s.id == 99001 then new = s end end
    t.ok(new and new.kind == "cast" and new.trigger == "seen", "new spell joins the Shaman's casts")
    t.eq(B.DefaultPriority(new), "should", "interrupted in play: should by default")
    t.ok(entry.seen[9532] ~= nil, "known spell marked seen")
    t.eq(#MK.Abilities.Spells(entry), 3, "data spells kept, the new one added once")

    -- Same fight again: counts go up, nothing new.
    t.eq(B.ReadMeter(), 0, "re-read: nothing new")
    t.eq(rec(RFC, "Ragefire Shaman", 9532).n, 3, "seen count grows (fight + 2 reads)")

    -- 2. Two casters in the pull: an unknown kick stays unattributed; a known one still lands.
    enemies = { { name = "Searing Blade Cultist", classFilename = "PALADIN" }, { name = "Searing Blade Warlock", classFilename = "MAGE" } }
    spells = { [5] = { [GUID_ME] = { kick(99002), kick(20791) } } }
    fight()
    t.eq(rec(RFC, "Searing Blade Cultist", 99002), nil, "ambiguous: not given to the Cultist")
    t.eq(rec(RFC, "Searing Blade Warlock", 99002), nil, "nor to the Warlock")
    t.ok(rec(RFC, "Searing Blade Warlock", 20791), "Shadow Bolt: only the Warlock casts it")

    -- 3. A Forever-only dungeon without data fills from play.
    local KROLDOK = 3002
    MK.Plates.instanceID = KROLDOK
    env.GetInstanceInfo = function() return "Krol'dok Stronghold", "party", 1, "Normal", 5, 0, false, KROLDOK, 5, nil, false end
    enemies = { { name = "Twilight Grunt", classFilename = "WARRIOR" }, { name = "Twilight Shaman", classFilename = "MAGE" } }
    spells = { [7] = { [GUID_ME] = { hit(99003, "Twilight Grunt") } }, [5] = { [GUID_LUMEN] = { kick(99004) } } }
    fight()
    t.ok(rec(KROLDOK, "Twilight Grunt", 99003), "no data: hit recorded")
    t.ok(rec(KROLDOK, "Twilight Shaman", 99004), "no data: kick pinned to the only caster")
    t.eq(B.LearnedInstances()[KROLDOK], "Krol'dok Stronghold", "instance name kept")
    local rows = B.AbilityRows(KROLDOK)
    t.ok(#rows == 4 and rows[1].mob == "Twilight Grunt" and rows[3].mob == "Twilight Shaman", "page rows for learned mobs")
    t.ok(rows[4].seen and rows[4].auto == "should", "Shadow Hex: seen, should")
    t.eq(rows[2].auto, "ignore", "Grunt Smash (instant hit): ignore")
    -- In the briefing: a Twilight Shaman in view brings Shadow Hex under best effort.
    sim.units.nameplate1 = { name = "Twilight Shaman", friendly = false, level = 30, tier = "elite", power = "MANA" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    sim:Advance(1)
    MK.Plates.instanceID = KROLDOK
    local lines = B.BuildLines((B.Plan()))
    t.eq(lines[1], "[Bulwark] Best effort: Shadow Hex", "learned cast briefed")

    -- 4. Guards: open world, combat.
    MK.Plates.inInstance = false
    t.eq(B.ReadMeter(), 0, "open world: not read")
    MK.Plates.inInstance = true
    sim:EnterCombat()
    t.eq(B.ReadMeter(), 0, "in combat: not read")
    sim:LeaveCombat()

    -- 5. Page: the learned dungeon is offered; seen spells carry the mark.
    local page = H.page(sim, "briefing")
    page.instance = KROLDOK
    page:refresh()
    t.contains({ page.zoneDrop.label:GetText() }, "Krol'dok Stronghold", "learned dungeon in the picker")
    t.contains({ page.rows[4].spell:GetText() }, "ReadyCheck%-Ready", "seen mark on Shadow Hex")
    t.eq(#sim.errors, 0, "no Lua errors")
end
