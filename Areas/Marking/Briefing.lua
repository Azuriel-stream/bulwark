local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Briefing (kb/addons/Bulwark-Briefing.md): before a pull, tell the group which casts of the pack in view must be
-- interrupted. Out of combat only: others' casts are secret in combat and boss encounters block addon chat.
-- Build step 1: the priority engine and /bwk mark brief [preview] for the planned pack + the target.
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
    if spell.kind == "passive" or spell.kind == "other" or OUT_OF_FIGHT[spell.trigger] then return "ignore" end
    if not Abilities.Interruptible(spell) then return "ignore" end
    if spell.kind == "heal" or spell.kind == "cc" then return "must" end
    if spell.channel or spell.cast >= SHOULD_CAST then return "should" end
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
    if override and Briefing.RANK[override.prio] then
        return override.prio, "user", override.note or (hint and hint.note), deadly
    end
    if hint then
        if flags.deadly or flags.interrupt then return "must", "hint", hint.note, deadly end
        for _, f in ipairs(INFO_FLAGS) do
            if flags[f] then return "info", "hint", hint.note, deadly end
        end
    end
    return Briefing.DefaultPriority(spell), "data", nil, false
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
function Briefing.MobSpells(entry, lookup)
    local byID, list, ignored = {}, {}, 0
    for i, spell in ipairs(Abilities.Spells(entry)) do
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
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(name) == "string" and not Utils.IsSecret(name) and name ~= "" then return name end
    return "#" .. id
end
Briefing.SpellName = SpellName

local function Names(items, prio)
    local names, seen = {}, {}
    for _, item in ipairs(items) do
        if item.prio == prio then
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

-- Chat lines for a briefed pack. mobs = { { name, icon?, count?, spells = MobSpells list } } in kill order.
--   [Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave; {rt4} Ragefire Shaman: Healing Wave
--   [Bulwark] Best effort: Lightning Bolt, Shadow Bolt
--   [Bulwark] Note: Leech Poison (Witherfang): Poisons the tank.
-- Plain spell names, never links (kb/gotchas.md#spell-link-chat); no bare "|" (#chat-pipe). Empty when there is
-- nothing to say.
function Briefing.BuildLines(mobs)
    local interrupt, best, notes, mustNames, bestSeen = {}, {}, {}, {}, {}
    for _, mob in ipairs(mobs) do
        local must = Names(mob.spells, "must")
        if #must > 0 then
            interrupt[#interrupt + 1] = Briefing.MobLabel(mob) .. ": " .. table.concat(must, ", ")
            for _, n in ipairs(must) do mustNames[n] = true end
        end
        for _, item in ipairs(mob.spells) do
            if item.prio == "info" and item.note and item.note ~= "" then
                notes[#notes + 1] = SpellName(item.spell.id) .. " (" .. mob.name .. "): " .. item.note
            end
        end
    end
    for _, mob in ipairs(mobs) do
        for _, n in ipairs(Names(mob.spells, "should")) do
            if not mustNames[n] and not bestSeen[n] then bestSeen[n], best[#best + 1] = true, n end
        end
    end
    local Wrap, lines = MK.Team.Wrap, {}
    for _, l in ipairs(Wrap(L["BRIEF_INTERRUPT"], interrupt, "; ")) do lines[#lines + 1] = l end
    for _, l in ipairs(Wrap(L["BRIEF_BEST_EFFORT"], best, ", ")) do lines[#lines + 1] = l end
    for _, l in ipairs(Wrap(L["BRIEF_NOTE"], notes, "; ")) do lines[#lines + 1] = l end
    for i, l in ipairs(lines) do lines[i] = l:gsub("|", "/") end   -- a mob or note can't break the message
    return lines
end

-- =========================================================================
-- Shell: which mobs are in front of the tank.
-- =========================================================================

-- Curated hint / user override for a mob's spell. Hints arrive with build step 6 (MK.BriefingHints, generated),
-- overrides with step 4 (BulwarkDB.marking.briefing.overrides[mob][spellID]).
local function Lookup(instanceID, name)
    local hints = MK.BriefingHints and MK.BriefingHints[instanceID]
    hints = hints and hints[name]
    local saved = MK.db and MK.db.briefing and MK.db.briefing.overrides
    saved = saved and saved[name]
    if not hints and not saved then return nil end
    return function(id) return hints and hints[id], saved and saved[id] end
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
        local entry, realName = Abilities.Find(name, instanceID)
        if not name then
            summary.unknown = summary.unknown + 1
        elseif not entry then
            summary.noData[name] = (summary.noData[name] or 0) + 1
        else
            local spells, ignored = Briefing.MobSpells(entry, Lookup(instanceID, realName))
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

-- Chat text for the local print: {rtN} as the icon.
local function Display(text)
    return (text:gsub("{rt(%d)}", function(n) return Utils.IconText(tonumber(n)) end))
end

local PRIO_COLOR = { must = "ffff5555", should = "ffffd100", info = "ff66ccff" }

-- /bwk mark brief preview: what Briefing sees and would post, printed locally.
function Briefing.Preview()
    local mobs, summary = Briefing.Collect()
    MK:Print(L["BRIEF_PREVIEW_HEADER"], summary.total)
    for _, mob in ipairs(mobs) do
        local parts = {}
        for _, item in ipairs(mob.spells) do
            parts[#parts + 1] = string.format("|c%s%s|r %s%s", PRIO_COLOR[item.prio], L["BRIEF_PRIO_" .. item.prio],
                SpellName(item.spell.id), item.source ~= "data" and (" (" .. L["BRIEF_SRC_" .. item.source] .. ")") or "")
        end
        local label = Display(Briefing.MobLabel(mob)) .. (mob.boss and (" " .. L["BRIEF_BOSS"]) or "")
        print("  " .. label .. ": " .. (#parts > 0 and table.concat(parts, ", ") or L["BRIEF_NOTHING_TO_KICK"]))
    end
    local names = {}
    for name, n in pairs(summary.noData) do names[#names + 1] = n > 1 and string.format(L["BRIEF_COUNT"], n, name) or name end
    table.sort(names)
    if #names > 0 then print("  " .. string.format(L["BRIEF_NO_DATA"], table.concat(names, ", "))) end
    if summary.unknown > 0 then print("  " .. string.format(L["BRIEF_UNKNOWN"], summary.unknown)) end
    local lines = Briefing.BuildLines(mobs)
    if #lines == 0 then
        print("  " .. L["BRIEF_NOTHING"])
    else
        print("  " .. L["BRIEF_WOULD_POST"])
        for _, l in ipairs(lines) do print("    " .. Display(l)) end
    end
end

-- /bwk mark brief: post it. Out of combat only (the plan is for the pull; in a boss fight chat is blocked anyway).
function Briefing.Post()
    if InCombatLockdown() then
        MK:Print(L["BRIEF_IN_COMBAT"])
        return false
    end
    local mobs, summary = Briefing.Collect()
    local lines = Briefing.BuildLines(mobs)
    if #lines == 0 then
        MK:Print(L["BRIEF_NOTHING"])
        if summary.unknown > 0 then MK:Print(L["BRIEF_UNKNOWN"], summary.unknown) end
        return false
    end
    MK.Team:Send(lines)
    return true
end
