local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Briefing (kb/addons/Bulwark-Briefing.md): before a pull, tell the group which casts of the pack in view must be
-- interrupted. Out of combat only: others' casts are secret in combat and boss encounters block addon chat.
-- Build step 1: the priority engine and /bwk mark brief [preview] for the planned pack + the target.
-- Build step 2: who interrupts which mob (KIT, KitFor, Assign, Roster).
-- Build step 3: the tile and the "Post briefing" key (BriefingTile.lua).
-- Build step 5: casts seen in play, learned from the damage meter after each fight (ReadMeter, FindEntry).
-- Build step 6: curated hints (MK.BriefingHints, generated from tools/data/briefing-hints.json): per spell, or per
-- mechanic ("@Patrol": no spell) shown and posted like a cast with a note.
-- Later steps: interrupter assignment (2), tile + keybind (3), per-ability edits on the Mobs page (4), learning
-- from the damage meter (5), curated hints in the generated data (6).
local Briefing = {}
MK.Briefing = Briefing
local L, Utils, Abilities = MK.L, MK.Utils, MK.Abilities

-- =========================================================================
-- Pure part (no WoW API apart from spell names): tests drive these directly.
-- =========================================================================

Briefing.RANK = { must = 3, should = 2, info = 1, ignore = 0 }

-- Triggers that never fire during the fight (pre-pull buffs, summons before the pull, on death, ...).
local OUT_OF_FIGHT = { ooc = true, spawn = true, death = true, home = true, evade = true, kill = true }
-- Among equal priorities: a heal undoes the group's work, crowd control takes a player out, then the rest.
local KIND_WEIGHT = { heal = 6, cc = 5, summon = 4, buff = 3, dmg = 2, dot = 2, debuff = 2, knock = 1 }
local SHOULD_CAST = 2000   -- ms: a damage/debuff cast this long is worth a kick when someone is free

-- Default priority from the data alone. must: interruptible heal or crowd control. should: any other interruptible
-- cast of 2 s or more, or channelled. ignore: instant, passive, or only outside the fight.
function Briefing.DefaultPriority(spell)
    if spell.kind == "passive" or OUT_OF_FIGHT[spell.trigger] then return "ignore" end
    -- "other": the game's data gives no clear effect (e.g. Mana Burn). Instant: noise. With a cast, channelled or
    -- interrupted in logs: a cast like any other (falls through to the should rule below).
    if spell.kind == "other" and not Abilities.Interruptible(spell) then return "ignore" end
    if spell.kind == "cast" then return "should" end   -- seen interrupted in play, kind unknown: worth a kick
    -- Instant fear, charm or sleep (flag F): nothing to kick, but a shaman's Tremor Totem breaks it (Assign).
    if not Abilities.Interruptible(spell) then return spell.tremor and "info" or "ignore" end
    -- Can't be kicked (flag N): a heal or crowd control still matters (a stun stops it, else the group is warned);
    -- "kick it when free" means nothing for the rest.
    if spell.kind == "heal" or spell.kind == "cc" then return "must" end
    if spell.nokick then return "ignore" end
    if spell.channel or spell.cast >= SHOULD_CAST or spell.kicked then return "should" end   -- kicked: groups stop it in logs
    return "ignore"
end

local function FlagSet(flags)
    local set = {}
    for k, v in pairs(flags or {}) do
        if type(k) == "number" then set[v] = true elseif v then set[k] = true end
    end
    return set
end

local INFO_FLAGS = { "dispel-magic", "dispel-curse", "dispel-poison", "purge", "tank", "healer", "important", "cc" }

-- Priority of one mob ability: the user's override (Mobs page, step 4) > a curated hint (step 6) > the data rules.
-- hint = { flags = { "interrupt", ... } or { interrupt = true }, note = "..." }; override = { prio = "...", note = "..." }
-- Returns prio, source ("user" | "hint" | "data"), note, deadly.
function Briefing.Priority(spell, hint, override)
    local flags = FlagSet(hint and hint.flags)
    local deadly = flags.deadly == true
    -- Your note counts with any priority, also with Auto (override without prio).
    local note = (override and override.note) or (hint and hint.note)
    if override and Briefing.RANK[override.prio] then
        return override.prio, "user", note, deadly
    end
    if hint then
        if flags.deadly or flags.interrupt then return "must", "hint", note, deadly end
        for _, f in ipairs(INFO_FLAGS) do
            if flags[f] then return "info", "hint", note, deadly end
        end
    end
    return Briefing.DefaultPriority(spell), "data", override and override.note or nil, false
end

local function Better(a, b)
    local ra, rb = Briefing.RANK[a.prio], Briefing.RANK[b.prio]
    if ra ~= rb then return ra > rb end
    if a.deadly ~= b.deadly then return a.deadly end
    local ka, kb = KIND_WEIGHT[a.spell.kind] or 0, KIND_WEIGHT[b.spell.kind] or 0
    if ka ~= kb then return ka > kb end
    return a.order < b.order
end

-- The abilities of one data entry that matter, best first: { { spell, prio, source, note, deadly, order } }.
-- A spell listed twice (two triggers) counts once, at its best priority. Also returns how many were ignored.
-- lookup(spellID) -> hint, override (both optional).
-- The entry's casts (Abilities.Spells) plus its curated mechanics: { id = "@Patrol", kind = "note" } pseudo casts.
function Briefing.EntrySpells(entry)
    local list = Abilities.Spells(entry)
    for _, key in ipairs(entry and entry.mechanics or {}) do
        list[#list + 1] = { id = key, kind = "note", cast = 0, trigger = "hint", rmin = 0, rmax = 0 }
    end
    return list
end

function Briefing.MobSpells(entry, lookup)
    local byID, list, ignored = {}, {}, 0
    for i, spell in ipairs(Briefing.EntrySpells(entry)) do
        local hint, override
        if lookup then hint, override = lookup(spell.id) end
        local prio, source, note, deadly = Briefing.Priority(spell, hint, override)
        local item = { spell = spell, prio = prio, source = source, note = note, deadly = deadly, order = i }
        local old = byID[spell.id]
        if not old then
            byID[spell.id] = item
            list[#list + 1] = item
        elseif Better(item, old) then
            for k, v in pairs(item) do if k ~= "order" then old[k] = v end end
        end
    end
    local kept = {}
    for _, item in ipairs(list) do
        if item.prio == "ignore" then ignored = ignored + 1 else kept[#kept + 1] = item end
    end
    table.sort(kept, Better)
    return kept, ignored
end

local function SpellName(id)
    if type(id) == "string" then return (id:gsub("^@", "")) end   -- a curated mechanic ("@Patrol")
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(name) == "string" and not Utils.IsSecret(name) and name ~= "" then return name end
    return "#" .. id
end
Briefing.SpellName = SpellName

local function Names(items, prio)
    local names, seen = {}, {}
    for _, item in ipairs(items) do
        if item.prio == prio and not item.totem then
            local name = SpellName(item.spell.id)
            if not seen[name] then seen[name], names[#names + 1] = true, name end
        end
    end
    return names
end

-- "{rt8} Ragefire Shaman", "2x Ragefire Shaman"
function Briefing.MobLabel(mob)
    local label = mob.name
    if mob.count and mob.count > 1 then label = string.format(L["BRIEF_COUNT"], mob.count, label) end
    if mob.icon then label = "{rt" .. mob.icon .. "} " .. label end
    return label
end

-- =========================================================================
-- Who interrupts (build step 2)
-- =========================================================================

-- Interrupts by class [data: wowf SpellLevels + SpellCooldowns, 2026-11-15]. kick = stops the cast and locks the
-- school; stun = stops it too, but with a long cooldown: used only when no kicker is left. Not assumed: Felhunter Spell
-- Lock (pet unknown), talents (Feral Charge, Concussion Blow, Silence), the SoD-era level-1 spells (Rebuke, Skull Bash,
-- Disrupt) [unverified for Forever players]. Warriors: Shield Bash needs a shield, Pummel Berserker Stance. The tank
-- (you) is read exactly (known spells, shield worn); another warrior is assumed a damage dealer: Pummel from 38.
-- ids = every player rank (SkillLineAbility); the first names it in chat.
Briefing.KIT = {
    SHAMAN  = { { id = 8042, ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, level = 4, cd = 6,
                  kind = "kick" } },                                                         -- Earth Shock
    ROGUE   = { { id = 1766, ids = { 1766, 1767, 1768, 1769 }, level = 12, cd = 10, kind = "kick" } },   -- Kick
    WARRIOR = { { id = 6552, ids = { 6552, 6554 }, level = 38, cd = 10, kind = "kick" },               -- Pummel
                { id = 72, ids = { 72, 1671, 1672 }, level = 12, cd = 12, kind = "kick", shield = true } }, -- Shield Bash
    MAGE    = { { id = 2139, ids = { 2139 }, level = 24, cd = 30, kind = "kick" } },                    -- Counterspell
    PALADIN = { { id = 853, ids = { 853, 5588, 5589, 10308 }, level = 8, cd = 60, kind = "stun" } },  -- Hammer of Justice
    DRUID   = { { id = 5211, ids = { 5211, 6798, 8983 }, level = 14, cd = 60, kind = "stun" } },     -- Bash (bear form)
}

-- Tremor Totem [data: wowf 8143, level 18, 300 s; 8145 pulses 8146 every 4 s, which dispels mechanics charm, fear and
-- sleep from party members in range]. Not an interrupt: it breaks fears (flag F), so those casts need no kicker.
Briefing.TREMOR = { id = 8143, ids = { 8143 }, level = 18 }

-- Whether a player drops Tremor Totem: shamans by level; you (own) by your spellbook.
function Briefing.HasTremor(class, level, own)
    if class ~= "SHAMAN" then return false end
    if own then return own.known(Briefing.TREMOR.ids) == true end
    return (tonumber(level) or 0) >= Briefing.TREMOR.level
end

-- The interrupt a player brings, or nil. own = { known = fn(ids), shield = bool } for the player (exact); others go
-- by class and level. Best = a kick before a stun, then the shorter cooldown.
function Briefing.KitFor(class, level, own)
    local best
    for _, k in ipairs(Briefing.KIT[class] or {}) do
        local has
        if own then
            has = own.known(k.ids) and (not k.shield or own.shield)
        else
            has = (tonumber(level) or 0) >= k.level and not k.shield
        end
        if has and (not best or (k.kind == "kick" and best.kind ~= "kick")
            or (k.kind == best.kind and k.cd < best.cd)) then
            best = k
        end
    end
    return best
end

-- Casts a Tremor Totem covers (item.totem, set by Assign) need no interrupter.
local function TopItem(mob, prio)
    for _, item in ipairs(mob.spells) do
        if item.prio == prio and not item.totem then return item end
    end
end

-- The must casts of a mob that this interrupt stops: a stun stops any cast, a kick only kickable ones (no flag N).
local function Stops(kit, spell)
    return kit.kind == "stun" or not spell.nokick
end

local function MustNamesFor(mob, kit)
    local names, seen = {}, {}
    for _, item in ipairs(mob.spells) do
        if item.prio == "must" and not item.totem and Stops(kit, item.spell) then
            local name = SpellName(item.spell.id)
            if not seen[name] then seen[name], names[#names + 1] = true, name end
        end
    end
    return names
end

-- Gives interrupters to the mobs with must casts. members = { { short, kit, tank? } } (kit nil = can't interrupt).
-- The tank takes the most important must (ties: kill order); then one interrupter per mob ("2x" groups need one each),
-- most important mob first, kickers by shortest cooldown, stunners last. A must that kicks can't stop (flag N) only
-- takes a stunner; stunners go to those mobs first. A tank left without a must takes the top kickable should of a boss
-- in view. A shaman in the group (member.tremor; the highest level) drops Tremor Totem for every listed fear, charm or
-- sleep (flag F): those casts get item.totem = that member and take no interrupter. Sets mob.assigned =
-- { { short, kit } } and mob.covers = spell names watched. Returns the members left over (the totem shaman still
-- interrupts).
function Briefing.Assign(mobs, members)
    local totem
    for _, m in ipairs(members) do
        local lv, best = tonumber(m.level) or 0, totem and (tonumber(totem.level) or 0)
        if m.tremor and (not totem or lv > best or (lv == best and m.short < totem.short)) then totem = m end
    end
    for _, mob in ipairs(mobs) do
        for _, item in ipairs(mob.spells) do
            item.totem = (totem and item.spell.tremor and item.prio ~= "ignore") and totem or nil
        end
    end
    local order = {}
    for i, mob in ipairs(mobs) do
        mob.assigned, mob.covers, mob.pos = {}, nil, i
        if TopItem(mob, "must") then order[#order + 1] = mob end
    end
    table.sort(order, function(a, b)
        local ia, ib = TopItem(a, "must"), TopItem(b, "must")
        if Better(ia, ib) ~= Better(ib, ia) then return Better(ia, ib) end
        return a.pos < b.pos
    end)
    local function Give(mob, member)
        mob.assigned[#mob.assigned + 1] = member
        mob.covers = mob.covers or {}
        local have = {}
        for _, n in ipairs(mob.covers) do have[n] = true end
        for _, n in ipairs(MustNamesFor(mob, member.kit)) do
            if not have[n] then mob.covers[#mob.covers + 1] = n end
        end
    end
    local function Wants(mob, member)
        return #mob.assigned < (mob.count or 1) and #MustNamesFor(mob, member.kit) > 0
    end
    local tank, others = nil, {}
    for _, m in ipairs(members) do
        if m.kit then
            if m.tank and not tank then tank = m else others[#others + 1] = m end
        end
    end
    table.sort(others, function(a, b)
        if a.kit.kind ~= b.kit.kind then return a.kit.kind == "kick" end
        if a.kit.cd ~= b.kit.cd then return a.kit.cd < b.kit.cd end
        return a.short < b.short
    end)
    if tank then
        for _, mob in ipairs(order) do
            if Wants(mob, tank) then Give(mob, tank); tank = nil; break end
        end
    end
    local used = {}
    local function Fill(mob, onlyStun)
        for i, m in ipairs(others) do
            if not used[i] and (not onlyStun or m.kit.kind == "stun") and Wants(mob, m) then
                Give(mob, m)
                used[i] = true
            end
        end
    end
    -- Stunners first to the mobs only they can stop (every must there kick-proof), then everyone by importance.
    for _, mob in ipairs(order) do
        if #MustNamesFor(mob, { kind = "kick" }) == 0 then Fill(mob, true) end
    end
    for _, mob in ipairs(order) do Fill(mob, false) end
    if tank then   -- no must in view: the tank watches the boss's worst cast
        local bestMob, bestItem
        for _, mob in ipairs(mobs) do
            local item = mob.boss and TopItem(mob, "should")
            if item and Stops(tank.kit, item.spell) and (not bestItem or Better(item, bestItem)) then
                bestMob, bestItem = mob, item
            end
        end
        if bestMob then
            bestMob.assigned[1] = tank
            bestMob.covers = { SpellName(bestItem.spell.id) }
            tank = nil
        end
    end
    local left = {}
    if tank then left[1] = tank end
    for i, m in ipairs(others) do
        if not used[i] then left[#left + 1] = m end
    end
    return left
end

-- Chat lines for a briefed pack. mobs = { { name, icon?, count?, spells = MobSpells list, assigned?, covers? } } in
-- kill order (Assign fills assigned/covers):
--   [Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave -> Tankard (Shield Bash); {rt4} Ragefire Shaman: ...
--   [Bulwark] Tremor Totem -> Rainclaw: Frightening Howl (Terrorhowl)   (fears a shaman's totem breaks)
--   [Bulwark] Best effort: Healing Wave, Lightning Bolt, Shadow Bolt   (musts nobody was free for come first)
--   [Bulwark] Can't interrupt: Frightening Howl (Terrorhowl)   (kick-proof musts no stunner covers: a heads-up)
--   [Bulwark] Note: Leech Poison (Witherfang): Poisons the tank.   (every listed cast with a note)
-- Plain spell names, never links (kb/gotchas.md#spell-link-chat); no bare "|" (#chat-pipe). Empty when there is
-- nothing to say.
function Briefing.BuildLines(mobs)
    local interrupt, best, notes, covered, mustNames, bestSeen, nokick, nokickSeen = {}, {}, {}, {}, {}, {}, {}, {}
    local tremor, tremorSeen, totem = {}, {}, nil
    local function AddBest(n)
        if not bestSeen[n] then bestSeen[n], best[#best + 1] = true, n end
    end
    for _, mob in ipairs(mobs) do
        local assigned = mob.assigned or {}
        local here = {}
        if #assigned > 0 then
            local who = {}
            for _, m in ipairs(assigned) do who[#who + 1] = m.short .. " (" .. SpellName(m.kit.id) .. ")" end
            interrupt[#interrupt + 1] = Briefing.MobLabel(mob) .. ": " .. table.concat(mob.covers, ", ") .. " -> "
                .. table.concat(who, ", ")
            for _, n in ipairs(mob.covers) do covered[n], here[n] = true, true end
        end
        local short = #assigned < (mob.count or 1)   -- nobody (or not enough) for this mob
        for _, item in ipairs(mob.spells) do
            if item.totem then
                totem = totem or item.totem
                local entry = SpellName(item.spell.id) .. " (" .. mob.name .. ")"
                if not tremorSeen[entry] then tremorSeen[entry], tremor[#tremor + 1] = true, entry end
            elseif item.prio == "must" then
                local n = SpellName(item.spell.id)
                mustNames[n] = true
                if item.spell.nokick then
                    local entry = n .. " (" .. mob.name .. ")"
                    if (short or not here[n]) and not nokickSeen[entry] then
                        nokickSeen[entry], nokick[#nokick + 1] = true, entry
                    end
                elseif short then
                    AddBest(n)
                end
            end
        end
        for _, item in ipairs(mob.spells) do
            if item.note and item.note ~= "" then   -- your note (or a hint's) on any listed cast
                notes[#notes + 1] = SpellName(item.spell.id) .. " (" .. mob.name .. "): " .. item.note
            end
        end
    end
    for _, mob in ipairs(mobs) do
        for _, n in ipairs(Names(mob.spells, "should")) do
            if not mustNames[n] and not covered[n] then AddBest(n) end
        end
    end
    local Wrap, lines = MK.Team.Wrap, {}
    for _, l in ipairs(Wrap(L["BRIEF_INTERRUPT"], interrupt, "; ")) do lines[#lines + 1] = l end
    if totem then
        for _, l in ipairs(Wrap(string.format(L["BRIEF_TREMOR"], totem.short), tremor, ", ")) do lines[#lines + 1] = l end
    end
    for _, l in ipairs(Wrap(L["BRIEF_BEST_EFFORT"], best, ", ")) do lines[#lines + 1] = l end
    for _, l in ipairs(Wrap(L["BRIEF_NO_KICK"], nokick, ", ")) do lines[#lines + 1] = l end
    for _, l in ipairs(Wrap(L["BRIEF_NOTE"], notes, "; ")) do lines[#lines + 1] = l end
    for i, l in ipairs(lines) do lines[i] = l:gsub("|", "/") end   -- a mob or note can't break the message
    return lines
end

-- =========================================================================
-- Shell: which mobs are in front of the tank.
-- =========================================================================

-- =========================================================================
-- Seen in play (build step 5). After every fight in an instance (2 s after combat ends: the meter is secret in
-- combat [in-game probe]) the damage meter tells, for each group member:
--   DamageTaken: which enemy (by name) hit them with which spell          -> learned, attributed exactly
--   Interrupts:  which enemy spell they stopped, but not whose (probe)     -> learned when the pull pins it to one mob
-- Saved per instance: BulwarkDB.marking.learnedSpells[instanceID] = { name = instance name,
--   mobs = { [mobName] = { [spellID] = { n = times, how = "hit"|"kick", at = time() } } } }
-- Known spells only get "seen"; new ones join the mob's casts (this is how Forever-only dungeons without data fill).
-- =========================================================================

local MELEE = { [6603] = true }   -- Attack (auto attack)

local function Store()
    local db = MK.db
    if not db then return {} end
    db.learnedSpells = db.learnedSpells or {}
    return db.learnedSpells
end

-- { [mobName] = { [spellID] = rec } } learned in an instance (empty table if none).
function Briefing.LearnedMobs(instanceID)
    local inst = instanceID and Store()[instanceID]
    return inst and inst.mobs or {}
end

-- Instances with learned casts: { [instanceID] = name }.
function Briefing.LearnedInstances()
    local list = {}
    for id, inst in pairs(Store()) do list[id] = inst.name or tostring(id) end
    return list
end

-- A learned spell as a data string: kind "cast" (interrupted: it has a cast) or "dmg" (it hit us), cast time from
-- the game, trigger "seen".
local function SeenSpell(id, rec)
    local cast = 0
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" and not Utils.IsSecret(info) then
        local c = info.castTime
        if type(c) == "number" and not Utils.IsSecret(c) then cast = c end
    end
    return string.format("%d;%s;%d;seen;0;0;", id, rec.how == "kick" and "cast" or "dmg", cast)
end

-- The mob's casts: the offline data merged with what was seen in play here. Returns entry, realName (nil if
-- neither knows the mob). entry.seen = { [spellID] = rec } for spells seen in play.
-- Also adds the mob's curated mechanics (entry.mechanics = { "@Patrol", ... }). Returns entry, realName, and the
-- instance whose hints apply (where the data found the mob, else the one given).
function Briefing.FindEntry(name, instanceID)
    local entry, realName, foundIn = Abilities.Find(name, instanceID)
    local where = foundIn or instanceID
    local key = realName or name
    local learned = Briefing.LearnedMobs(instanceID)[key]
    local hints = where and MK.BriefingHints and MK.BriefingHints[where] and MK.BriefingHints[where][key]
    local mechanics = {}
    for k in pairs(hints or {}) do if type(k) == "string" then mechanics[#mechanics + 1] = k end end
    table.sort(mechanics)
    if not learned and #mechanics == 0 then return entry, realName, where end
    local merged, have, ids = { boss = entry and entry.boss, seen = learned, mechanics = mechanics }, {}, {}
    for _, s in ipairs(entry or {}) do
        merged[#merged + 1] = s
        have[tonumber(s:match("^(%d+)"))] = true
    end
    for id in pairs(learned or {}) do if not have[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do merged[#merged + 1] = SeenSpell(id, learned[id]) end
    return merged, key, where
end

-- Records one sighting. A kick upgrades a hit (it proves the spell can be interrupted). Returns true if new.
function Briefing.RecordSeen(instanceID, instanceName, mob, spellID, how)
    local store = Store()
    local inst = store[instanceID] or { mobs = {} }
    store[instanceID] = inst
    inst.name = inst.name or instanceName
    inst.mobs[mob] = inst.mobs[mob] or {}
    local rec = inst.mobs[mob][spellID]
    if rec then
        rec.n = (rec.n or 0) + 1
        if how == "kick" then rec.how = "kick" end
        rec.at = time()
        return false
    end
    inst.mobs[mob][spellID] = { n = 1, how = how, at = time() }
    return true
end

-- Which mob of the pull cast an interrupted spell: the only one known to cast it (data or seen), else the only caster
-- type in the pull (creature unit class other than warrior/rogue, or the data's class). nil when it can't be pinned.
-- pull = { [name] = { caster = bool } }
function Briefing.Attribute(spellID, pull, instanceID)
    local knows, casters = {}, {}
    for name, info in pairs(pull) do
        local entry = Briefing.FindEntry(name, instanceID)
        for _, spell in ipairs(Abilities.Spells(entry)) do
            if spell.id == spellID then knows[#knows + 1] = name break end
        end
        if info.caster then casters[#casters + 1] = name end
    end
    if #knows == 1 then return knows[1] end
    if #knows == 0 and #casters == 1 then return casters[1] end
    return nil
end

local NON_CASTER_CLASS = { WARRIOR = true, ROGUE = true }
local DATA_NON_CASTER = { [1] = true, [4] = true }   -- creature unit class 1 = warrior, 4 = rogue

local function Plain(v, kind)
    return v ~= nil and not Utils.IsSecret(v) and type(v) == kind
end

-- Reads the meter's current session (the fight that just ended). Returns how many new mob casts were learned.
function Briefing.ReadMeter()
    if not MK.isEnabled or not MK.Plates.inInstance or InCombatLockdown() then return 0 end
    local meter, E = C_DamageMeter, Enum
    if not (meter and meter.GetCombatSessionFromType and meter.GetCombatSessionSourceFromType and E
        and E.DamageMeterSessionType and E.DamageMeterType) then return 0 end
    local CURRENT, T = E.DamageMeterSessionType.Current, E.DamageMeterType
    local instanceID = MK.Plates.instanceID
    if not instanceID then return 0 end
    local okI, instanceName = pcall(GetInstanceInfo)
    instanceName = okI and Plain(instanceName, "string") and instanceName or nil

    -- Who was in the pull (enemy rows), and which of them cast spells.
    local pull = {}
    local ok, session = pcall(meter.GetCombatSessionFromType, CURRENT, T.EnemyDamageTaken)
    local sources = ok and Plain(session, "table") and session.combatSources
    for _, src in ipairs(Plain(sources, "table") and sources or {}) do
        local name = Plain(src, "table") and src.name
        if Plain(name, "string") and name ~= "" and src.isLocalPlayer ~= true then
            local entry = Abilities.Find(name, instanceID)
            local cls = src.classFilename
            local caster
            if entry and entry.cls and entry.cls > 0 then
                caster = not DATA_NON_CASTER[entry.cls]
            else
                caster = Plain(cls, "string") and cls ~= "" and not NON_CASTER_CLASS[cls] or false
            end
            pull[name] = { caster = caster }
        end
    end

    local members = {}
    for _, m in ipairs(MK.Team:Members()) do members[m.short or m.name] = true end
    local new = 0
    local function Spells(unit, meterType)
        local okG, guid = pcall(UnitGUID, unit)
        if not okG or not Plain(guid, "string") then return {} end
        local okS, src = pcall(meter.GetCombatSessionSourceFromType, CURRENT, meterType, guid)
        local list = okS and Plain(src, "table") and src.combatSpells
        return Plain(list, "table") and list or {}
    end
    for _, m in ipairs(MK.Team:Members()) do
        -- Hits: the enemy's name comes with each spell.
        for _, sp in ipairs(Spells(m.unit, T.DamageTaken)) do
            local id = Plain(sp, "table") and sp.spellID
            local det = Plain(sp, "table") and sp.combatSpellDetails
            local mob = Plain(det, "table") and det.unitName
            if Plain(id, "number") and not MELEE[id] and Plain(mob, "string") and mob ~= "" and det.isMob == true
                and not members[mob] then
                if Briefing.RecordSeen(instanceID, instanceName, mob, id, "hit") then new = new + 1 end
            end
        end
        -- Kicks: the interrupted spell, caster unknown.
        for _, sp in ipairs(Spells(m.unit, T.Interrupts)) do
            local id = Plain(sp, "table") and sp.spellID
            if Plain(id, "number") then
                local mob = Briefing.Attribute(id, pull, instanceID)
                if mob then
                    if Briefing.RecordSeen(instanceID, instanceName, mob, id, "kick") then new = new + 1 end
                else
                    MK:Debug("briefing: interrupted spell %d not attributed (pull of %d)", id, (function()
                        local n = 0
                        for _ in pairs(pull) do n = n + 1 end
                        return n
                    end)())
                end
            end
        end
    end
    if new > 0 then
        MK:Debug("briefing: %d new cast(s) seen in play", new)
        MK:Fire("BRIEFING_CHANGED")
    end
    return new
end

-- =========================================================================
-- Your edits (build step 4, Marking > Briefing page): per mob name and spell, a priority and/or a note.
-- BulwarkDB.marking.briefing.overrides[mobName][spellID] = { prio = "must"|"should"|"info"|"ignore"|nil, note = "..." }
-- By name, not per dungeon: a mob's casts are the same wherever its name appears.
-- =========================================================================

function Briefing.Overrides()
    local db = MK.db
    if not db then return {} end
    db.briefing = db.briefing or {}
    db.briefing.overrides = db.briefing.overrides or {}
    return db.briefing.overrides
end

function Briefing.GetOverride(mob, spellID)
    local byMob = Briefing.Overrides()[mob]
    return byMob and byMob[spellID]
end

-- prio nil = automatic; note nil/"" = none. Both empty: the entry goes away.
function Briefing.SetOverride(mob, spellID, prio, note)
    local all = Briefing.Overrides()
    if prio ~= nil and not Briefing.RANK[prio] then prio = nil end
    note = note and strtrim(note) or nil
    if note == "" then note = nil end
    all[mob] = all[mob] or {}
    if prio or note then
        all[mob][spellID] = { prio = prio, note = note }
    else
        all[mob][spellID] = nil
        if next(all[mob]) == nil then all[mob] = nil end
    end
    MK:Fire("BRIEFING_CHANGED")
end

-- Curated hint (build step 6: MK.BriefingHints, generated) and your override for a mob's spell.
local function Lookup(instanceID, name)
    local hints = MK.BriefingHints and MK.BriefingHints[instanceID]
    hints = hints and hints[name]
    local saved = Briefing.Overrides()[name]
    if not hints and not saved then return nil end
    return function(id) return hints and hints[id], saved and saved[id] end
end

-- Rows for the Briefing page: every mob of an instance with ability data (bosses last, else by name), then each of
-- its casts once (passives left out): { mob = name, boss = bool } and { mob, spell, auto, autoSource, override }.
-- auto = the priority without your override (data rules or a hint).
function Briefing.AbilityRows(instanceID)
    local mobs = {}
    for name in pairs(MK.MobAbilities and MK.MobAbilities[instanceID] or {}) do mobs[name] = true end
    for name in pairs(Briefing.LearnedMobs(instanceID)) do mobs[name] = true end
    local names, entries = {}, {}
    for name in pairs(mobs) do
        names[#names + 1] = name
        entries[name] = Briefing.FindEntry(name, instanceID)
    end
    table.sort(names, function(a, b)
        local ba, bb = entries[a].boss == true, entries[b].boss == true
        if ba ~= bb then return bb end
        return a < b
    end)
    local rows = {}
    for _, name in ipairs(names) do
        local entry = entries[name]
        local hints = MK.BriefingHints and MK.BriefingHints[instanceID] and MK.BriefingHints[instanceID][name]
        local spells, seen = {}, {}
        for _, spell in ipairs(Briefing.EntrySpells(entry)) do
            if spell.kind ~= "passive" and not seen[spell.id] then
                seen[spell.id] = true
                local auto, source = Briefing.Priority(spell, hints and hints[spell.id], nil)
                local hint = hints and hints[spell.id]
                spells[#spells + 1] = { mob = name, spell = spell, auto = auto, autoSource = source,
                                        override = Briefing.GetOverride(name, spell.id),
                                        seen = entry.seen and entry.seen[spell.id],
                                        hintNote = hint and hint.note ~= "" and hint.note or nil }
            end
        end
        if #spells > 0 then
            rows[#rows + 1] = { mob = name, boss = entry.boss == true }
            for _, r in ipairs(spells) do rows[#rows + 1] = r end
        end
    end
    return rows
end

-- The mobs to brief: the planner's candidates (near, alive, hostile, out of combat, the Shift-hover selection if
-- any; marked or not) plus the target. Name: readable > learned (%t) > unique data name; nameless plates are counted
-- but never guessed. Icon: the mark the mob wears as far as Marking knows (our marks, learned marks).
-- Returns mobs (kill order: marked mobs by the Team ladder, then unmarked) and a summary.
function Briefing.Collect()
    local Plates = MK.Plates
    local recs, seenRec = {}, {}
    local candidates = Plates:GetCandidates()
    for _, rec in ipairs(candidates) do recs[#recs + 1], seenRec[rec] = rec, true end
    local target = UnitExists("target") and Plates:RecordFor("target")
    if target and not seenRec[target] and target.hostile and not target.dead and not target.player then
        recs[#recs + 1] = target
    end

    local iconOf = {}
    for icon, rec in pairs(MK.Learn.MobsByIcon()) do iconOf[rec] = icon end
    local ladderPos = {}
    for i, icon in ipairs(MK.Team:GetLadder()) do ladderPos[icon] = i end

    local instanceID = Plates.instanceID
    local summary = { total = #recs, unknown = 0, noData = {}, ignored = 0 }
    local mobs, byName = {}, {}
    for _, rec in ipairs(recs) do
        local name = MK.Learn.NameOf(rec)
        local entry, realName, hintsIn = Briefing.FindEntry(name, instanceID)
        if not name then
            summary.unknown = summary.unknown + 1
        elseif not entry then
            summary.noData[name] = (summary.noData[name] or 0) + 1
        else
            local spells, ignored = Briefing.MobSpells(entry, Lookup(hintsIn, realName))
            summary.ignored = summary.ignored + ignored
            local icon = iconOf[rec]
            local key = not icon and realName
            if key and byName[key] then
                byName[key].count = byName[key].count + 1
            else
                local mob = { name = realName, icon = icon, count = 1, spells = spells, boss = entry.boss == true,
                              rec = rec, seq = rec.seq or 0 }
                mobs[#mobs + 1] = mob
                if key then byName[key] = mob end
            end
        end
    end
    table.sort(mobs, function(a, b)
        local pa = a.icon and (ladderPos[a.icon] or 9) or 10
        local pb = b.icon and (ladderPos[b.icon] or 9) or 10
        if pa ~= pb then return pa < pb end
        if a.icon ~= b.icon then return (a.icon or 0) > (b.icon or 0) end
        return a.seq < b.seq
    end)
    return mobs, summary
end

-- The group as interrupters: { short, class, level, kit, tank } per living, connected member. You are the tank
-- (Bulwark is a tank's addon), read exactly from your spellbook and off-hand.
function Briefing.Roster()
    local list = {}
    for _, m in ipairs(MK.Team:Members()) do
        if m.alive then
            local isMe = m.unit == "player" or UnitIsUnit(m.unit, "player") == true
            local own = isMe and { known = NS.Utils.KnowsAny, shield = NS.Utils.HasShield() } or nil
            list[#list + 1] = { short = m.short or m.name, class = m.class, level = m.level, tank = isMe,
                                kit = Briefing.KitFor(m.class, m.level, own),
                                tremor = Briefing.HasTremor(m.class, m.level, own) }
        end
    end
    return list
end

-- Collect + Assign: mobs (with assignments), summary, roster, members left over.
function Briefing.Plan()
    local mobs, summary = Briefing.Collect()
    local roster = Briefing.Roster()
    local left = Briefing.Assign(mobs, roster)
    return mobs, summary, roster, left
end

-- Chat text for the local print: {rtN} as the icon.
local function Display(text)
    return (text:gsub("{rt(%d)}", function(n) return Utils.IconText(tonumber(n)) end))
end
Briefing.Display = Display

local PRIO_COLOR = { must = "ffff5555", should = "ffffd100", info = "ff66ccff" }

-- /bwk mark brief preview: what Briefing sees and would post, printed locally.
function Briefing.Preview()
    local mobs, summary, roster = Briefing.Plan()
    MK:Print(L["BRIEF_PREVIEW_HEADER"], summary.total)
    for _, mob in ipairs(mobs) do
        local parts = {}
        for _, item in ipairs(mob.spells) do
            local tags = {}
            if item.source ~= "data" then tags[#tags + 1] = L["BRIEF_SRC_" .. item.source] end
            if item.spell.nokick then tags[#tags + 1] = L["BRIEF_NO_KICK_MARK"] end
            if item.totem then tags[#tags + 1] = L["BRIEF_TREMOR_MARK"] end
            parts[#parts + 1] = string.format("|c%s%s|r %s%s", PRIO_COLOR[item.prio], L["BRIEF_PRIO_" .. item.prio],
                SpellName(item.spell.id), #tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or "")
        end
        local label = Display(Briefing.MobLabel(mob)) .. (mob.boss and (" " .. L["BRIEF_BOSS"]) or "")
        print("  " .. label .. ": " .. (#parts > 0 and table.concat(parts, ", ") or L["BRIEF_NOTHING_TO_KICK"]))
    end
    local names = {}
    for name, n in pairs(summary.noData) do names[#names + 1] = n > 1 and string.format(L["BRIEF_COUNT"], n, name) or name end
    table.sort(names)
    if #names > 0 then print("  " .. string.format(L["BRIEF_NO_DATA"], table.concat(names, ", "))) end
    if summary.unknown > 0 then print("  " .. string.format(L["BRIEF_UNKNOWN"], summary.unknown)) end
    local can, cannot = {}, {}
    for _, m in ipairs(roster) do
        if m.kit then
            can[#can + 1] = string.format("%s (%s, %d s)", m.short, SpellName(m.kit.id), m.kit.cd)
        else
            cannot[#cannot + 1] = m.short
        end
    end
    print("  " .. string.format(L["BRIEF_INTERRUPTERS"], #can > 0 and table.concat(can, ", ") or L["BRIEF_NONE"]))
    if #cannot > 0 then print("  " .. string.format(L["BRIEF_NO_KIT"], table.concat(cannot, ", "))) end
    local lines = Briefing.BuildLines(mobs)
    if #lines == 0 then
        print("  " .. L["BRIEF_NOTHING"])
    else
        print("  " .. L["BRIEF_WOULD_POST"])
        for _, l in ipairs(lines) do print("    " .. Display(l)) end
    end
end

-- /bwk mark brief: post it. Out of combat only (the plan is for the pull; in a boss fight chat is blocked anyway).
-- Returns the lines sent (or printed, solo), nil if nothing went out.
function Briefing.Post()
    if InCombatLockdown() then
        MK:Print(L["BRIEF_IN_COMBAT"])
        return nil
    end
    local mobs, summary = Briefing.Plan()
    local lines = Briefing.BuildLines(mobs)
    if #lines == 0 then
        MK:Print(L["BRIEF_NOTHING"])
        if summary.unknown > 0 then MK:Print(L["BRIEF_UNKNOWN"], summary.unknown) end
        return nil
    end
    MK.Team:Send(lines)
    return lines
end
