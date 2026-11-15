local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Briefing (kb/addons/Bulwark-Briefing.md): before a pull, tell the group which casts of the pack in view must be
-- interrupted. Out of combat only: others' casts are secret in combat and boss encounters block addon chat.
-- Build step 1: the priority engine and /bwk mark brief [preview] for the planned pack + the target.
-- Build step 2: who interrupts which mob (KIT, KitFor, Assign, Roster).
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

local function TopItem(mob, prio)
    for _, item in ipairs(mob.spells) do
        if item.prio == prio then return item end
    end
end

-- Gives interrupters to the mobs with must casts. members = { { short, kit, tank? } } (kit nil = can't interrupt).
-- The tank takes the most important must (ties: kill order); then one interrupter per mob ("2x" groups need one each),
-- most important mob first, kickers by shortest cooldown, stunners last. A tank left without a must takes the top
-- should of a boss in view. Sets mob.assigned = { { short, kit } } and mob.covers = spell names watched.
-- Returns the members left over.
function Briefing.Assign(mobs, members)
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
        mob.covers = mob.covers or Names(mob.spells, "must")
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
    if tank and order[1] then
        Give(order[1], tank)
        tank = nil
    end
    local nextOther = 1
    for _, mob in ipairs(order) do
        while #mob.assigned < (mob.count or 1) and others[nextOther] do
            Give(mob, others[nextOther])
            nextOther = nextOther + 1
        end
    end
    if tank then   -- no must in view: the tank watches the boss's worst cast
        local bestMob, bestItem
        for _, mob in ipairs(mobs) do
            local item = mob.boss and TopItem(mob, "should")
            if item and (not bestItem or Better(item, bestItem)) then bestMob, bestItem = mob, item end
        end
        if bestMob then
            bestMob.assigned[1] = tank
            bestMob.covers = { SpellName(bestItem.spell.id) }
            tank = nil
        end
    end
    local left = {}
    if tank then left[1] = tank end
    for i = nextOther, #others do left[#left + 1] = others[i] end
    return left
end

-- Chat lines for a briefed pack. mobs = { { name, icon?, count?, spells = MobSpells list, assigned?, covers? } } in
-- kill order (Assign fills assigned/covers):
--   [Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave -> Tankard (Shield Bash); {rt4} Ragefire Shaman: ...
--   [Bulwark] Best effort: Healing Wave, Lightning Bolt, Shadow Bolt   (musts nobody was free for come first)
--   [Bulwark] Note: Leech Poison (Witherfang): Poisons the tank.
-- Plain spell names, never links (kb/gotchas.md#spell-link-chat); no bare "|" (#chat-pipe). Empty when there is
-- nothing to say.
function Briefing.BuildLines(mobs)
    local interrupt, best, notes, covered, mustNames, bestSeen = {}, {}, {}, {}, {}, {}
    local function AddBest(n)
        if not bestSeen[n] then bestSeen[n], best[#best + 1] = true, n end
    end
    for _, mob in ipairs(mobs) do
        local assigned = mob.assigned or {}
        if #assigned > 0 then
            local who = {}
            for _, m in ipairs(assigned) do who[#who + 1] = m.short .. " (" .. SpellName(m.kit.id) .. ")" end
            interrupt[#interrupt + 1] = Briefing.MobLabel(mob) .. ": " .. table.concat(mob.covers, ", ") .. " -> "
                .. table.concat(who, ", ")
            for _, n in ipairs(mob.covers) do covered[n] = true end
        end
        local must = Names(mob.spells, "must")
        for _, n in ipairs(must) do mustNames[n] = true end
        if #must > 0 and #assigned < (mob.count or 1) then
            for _, n in ipairs(must) do AddBest(n) end   -- nobody (or not enough) for this mob
        end
        for _, item in ipairs(mob.spells) do
            if item.prio == "info" and item.note and item.note ~= "" then
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

-- The group as interrupters: { short, class, level, kit, tank } per living, connected member. You are the tank
-- (Bulwark is a tank's addon), read exactly from your spellbook and off-hand.
function Briefing.Roster()
    local list = {}
    for _, m in ipairs(MK.Team:Members()) do
        if m.alive then
            local isMe = m.unit == "player" or UnitIsUnit(m.unit, "player") == true
            local own = isMe and { known = NS.Utils.KnowsAny, shield = NS.Utils.HasShield() } or nil
            list[#list + 1] = { short = m.short or m.name, class = m.class, level = m.level, tank = isMe,
                                kit = Briefing.KitFor(m.class, m.level, own) }
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

local PRIO_COLOR = { must = "ffff5555", should = "ffffd100", info = "ff66ccff" }

-- /bwk mark brief preview: what Briefing sees and would post, printed locally.
function Briefing.Preview()
    local mobs, summary, roster = Briefing.Plan()
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
function Briefing.Post()
    if InCombatLockdown() then
        MK:Print(L["BRIEF_IN_COMBAT"])
        return false
    end
    local mobs, summary = Briefing.Plan()
    local lines = Briefing.BuildLines(mobs)
    if #lines == 0 then
        MK:Print(L["BRIEF_NOTHING"])
        if summary.unknown > 0 then MK:Print(L["BRIEF_UNKNOWN"], summary.unknown) end
        return false
    end
    MK.Team:Send(lines)
    return true
end
