local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Pure marking rules, ported from legacy TankMark v0.32 (Core/TankMark_Assignment.lua). No WoW API.
local Rules = {}
MK.Rules = Rules

-- creatureType -> the classes whose CC is legal on it. Forever has no player Hex (legacy Turtle WoW gave Troll
-- Shamans one), so Shamans bring no CC.
Rules.CCMap = {
    Humanoid  = { "MAGE", "ROGUE", "WARLOCK" },            -- Polymorph/Sap/Fear
    Beast     = { "MAGE", "DRUID", "HUNTER" },             -- Polymorph/Hibernate/Trap
    Elemental = { "WARLOCK" },                              -- Banish
    Demon     = { "WARLOCK" },                              -- Banish
    Undead    = { "PRIEST" },                               -- Shackle
    Dragonkin = { "DRUID" },                                -- Hibernate
}

function Rules.IsLegalCC(class, creatureType)
    local list = Rules.CCMap[creatureType]
    if not list then return false end
    for _, c in ipairs(list) do
        if c == class then return true end
    end
    return false
end

-- Whether a class brings any CC on Forever.
function Rules.HasCC(class)
    for _, list in pairs(Rules.CCMap) do
        for _, c in ipairs(list) do
            if c == class then return true end
        end
    end
    return false
end

-- The CC mechanics a class uses, as the immunity letters of Data/InstanceMobs.lua (F fear, Z sleep, T freeze,
-- K knockout, P polymorph, B banish, H shackle, S sapped). Sap is knockout or sapped depending on the client
-- data, so either immunity blocks it.
local CC_MECHANICS = { MAGE = "P", ROGUE = "KS", DRUID = "Z", HUNTER = "T", PRIEST = "H" }
function Rules.CCImmune(class, creatureType, immune)
    if not immune or immune == "" then return false end
    local mechanics = CC_MECHANICS[class]
    if class == "WARLOCK" then
        mechanics = (creatureType == "Demon" or creatureType == "Elemental") and "B" or "F"
    end
    if not mechanics then return false end
    for i = 1, #mechanics do
        if immune:find(mechanics:sub(i, i), 1, true) then return true end
    end
    return false
end

-- Pick a CC mark from the CC slots ({ mark, class, race, alive, used, disabled }), or nil.
-- Pass 1 prefers the authored class if legal; pass 2 takes the first legal slot. Unknown creature type
-- (inside instances when the offline data can't tell) degrades to authored-class-only; a mob the player taught as CC
-- without a class (taughtCC) takes the first eligible slot: the player vouched that it can be CC'd.
-- immune: the mob's CC immunity letters (offline data), or nil.
function Rules.SelectCCSlot(authoredClass, creatureType, slots, taughtCC, immune)
    local function eligible(s)
        return s.alive and not s.used and not s.disabled
            and not Rules.CCImmune(s.class, creatureType, immune)
    end
    if creatureType and Rules.CCMap[creatureType] then
        if authoredClass and Rules.IsLegalCC(authoredClass, creatureType) then
            for _, s in ipairs(slots) do
                if s.class == authoredClass and eligible(s) then return s.mark end
            end
        end
        for _, s in ipairs(slots) do
            if eligible(s) and Rules.IsLegalCC(s.class, creatureType) then return s.mark end
        end
        return nil
    end
    for _, s in ipairs(slots) do
        if eligible(s) and (s.class == authoredClass or (taughtCC and not authoredClass)) then return s.mark end
    end
    return nil
end

-- Mob role x tier -> default kill priority (lower = killed first). Legacy DATA-MODEL curve.
local ROLE_PRIO = {
    HEALER = { normal = 2, elite = 1, rare = 1, boss = 1 },
    CASTER = { normal = 3, elite = 2, rare = 2, boss = 1 },
    MELEE  = { normal = 5, elite = 4, rare = 3, boss = 1 },
}
local TIER_BUCKET = {
    normal = "normal", trivial = "normal", minus = "normal",
    elite = "elite",
    rare = "rare", rareelite = "rare",
    worldboss = "boss", boss = "boss",
}
function Rules.RoleTierPrio(role, tier)
    local row = ROLE_PRIO[role] or ROLE_PRIO.MELEE
    return row[TIER_BUCKET[tier] or "normal"]
end

-- How much a mob warrants a scarce CC slot (legacy CC_WORTH curve); 70+ = auto-CC candidate.
local CC_WORTH = {
    HEALER = { normal = 90, elite = 100, rare = 100, boss = 100 },
    CASTER = { normal = 40, elite = 70,  rare = 70,  boss = 80  },
    MELEE  = { normal = 10, elite = 30,  rare = 35,  boss = 40  },
}
function Rules.CCWorthiness(role, tier)
    local row = CC_WORTH[role] or CC_WORTH.MELEE
    return row[TIER_BUCKET[tier] or "normal"]
end

-- Rare and boss mobs are generally immune to player CC.
function Rules.CCTierEligible(tier)
    local bucket = TIER_BUCKET[tier] or "normal"
    return bucket == "normal" or bucket == "elite"
end

Rules.AUTO_CC_FLOOR = 70
function Rules.MeetsAutoCCFloor(role, tier)
    return Rules.CCWorthiness(role, tier) >= Rules.AUTO_CC_FLOOR
end

-- Forever: without a readable identity, a mana bar is the best role hint (casters and healers use mana).
function Rules.RoleFromPower(powerToken)
    if powerToken == "MANA" then return "CASTER" end
    return "MELEE"
end

-- Offline identity inside instances (Data/InstanceMobs.lua): the NPCs of one instance that use one model file.
local TYPE_NAMES = { B = "Beast", D = "Dragonkin", M = "Demon", E = "Elemental", G = "Giant", U = "Undead",
                     H = "Humanoid", C = "Critter", X = "Mechanical", N = "Not specified", T = "Totem" }
local POWER_CODES = { RAGE = "R", MANA = "M" }

-- variants: { "type;power;minLevel;maxLevel;immune;flags;name", ... } (flags: B = encounter boss). Keeps the
-- variants with the plate's power type (any, if unknown) and, when some match, its level. Returns nil when nothing
-- matches, else { ctype = creature type all of them share (nil if they disagree), immune = union of their
-- immunities, names = { unique names }, boss = all of them are encounter bosses }. Disagreement leaves the type
-- unknown, so a wrong guess never picks an illegal CC.
local function ParseVariant(v)
    local t, p, lo, hi, immune, flags, name = v:match("^(%u);(.);(%d+);(%d+);(%u*);(%u*);(.*)$")
    if not t then return nil end
    return { t = t, p = p, lo = tonumber(lo), hi = tonumber(hi), immune = immune, name = name,
             boss = flags:find("B", 1, true) ~= nil }
end

-- The variants with the plate's power type (any, if unknown), narrowed to the level range lo..hi when some overlap.
-- keep(row): optional extra filter.
local function MatchVariants(variants, powerToken, lo, hi, keep)
    local code = powerToken and (POWER_CODES[powerToken] or "?")
    local byPower, byLevel = {}, {}
    for _, v in ipairs(variants) do
        local row = ParseVariant(v)
        if row and (not code or row.p == code) and (not keep or keep(row)) then
            table.insert(byPower, row)
            if type(lo) == "number" and type(hi) == "number" and row.lo <= hi and row.hi >= lo then
                table.insert(byLevel, row)
            end
        end
    end
    return (#byLevel > 0) and byLevel or byPower
end

local function UniqueNames(rows)
    local names, seen = {}, {}
    for _, row in ipairs(rows) do
        if not seen[row.name] then seen[row.name] = true; table.insert(names, row.name) end
    end
    return names
end

-- Names for a learned signature entry (mob database window): the variants with its power type and boss-ness,
-- narrowed to the levels the entry was seen at. { name, ... }, possibly empty.
function Rules.NamesFromData(variants, powerToken, lo, hi, boss)
    return UniqueNames(MatchVariants(variants, powerToken, lo, hi, function(row) return row.boss == boss end))
end

function Rules.IdentifyFromData(variants, powerToken, level)
    local rows = MatchVariants(variants, powerToken, level, level)
    if #rows == 0 then return nil end
    local t, immune, seenLetter, boss = rows[1].t, "", {}, true
    for _, row in ipairs(rows) do
        if row.t ~= t then t = nil end
        if not row.boss then boss = false end
        for i = 1, #row.immune do
            local c = row.immune:sub(i, i)
            if not seenLetter[c] then seenLetter[c] = true; immune = immune .. c end
        end
    end
    return { ctype = t and TYPE_NAMES[t], immune = immune, names = UniqueNames(rows), boss = boss }
end

-- Signature: the readable fingerprint used to learn mobs where names are secret.
-- With the creature's model file ID (readable inside instances, kb/addons/TankMark.md run 6): "tier|power|model",
-- level-free, so one entry covers a mob type at every level (user decision). Without a model (the fallback if Blizzard
-- closes the loophole, and entries learned before): "level|tier|power", where level is the only extra separator.
function Rules.Signature(level, tier, powerToken, model)
    if model then
        return string.format("%s|%s|%s", tier or "?", powerToken or "?", tostring(model))
    end
    return string.format("%s|%s|%s", tostring(level or "?"), tier or "?", powerToken or "?")
end
