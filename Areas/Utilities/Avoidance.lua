local ADDON_NAME, NS = ...
local Utils = NS.Utils

-- Total avoidance: the attack table of a melee mob hitting the player (kb/addons/Bulwark-Utilities.md).
-- Two halves: Read() takes a snapshot of the character sheet (out of combat only: in combat the game hides these
-- values [in-game]); Compute() is plain math on a snapshot, so it can be tested and later fed edited values (what-if).
local Avoidance = NS:RegisterModule("Avoidance", "utilities")
local frame = CreateFrame("Frame")

-- Block cooldowns that can be counted in the table. Values [data] (tools/gamedata.ps1, build 70888).
-- The character sheet already includes an active one [in-game: Shield Block 10.76 -> 85.76], so Compute takes it out
-- again and adds it back only when the player ticks it.
Avoidance.BUFFS = {
    { key = "shieldBlock", class = "WARRIOR", ids = { 2565 }, block = 75, duration = 7, charges = 2 },
    { key = "holyShield", class = "PALADIN", ids = { 20925, 20927, 20928, 1239570 }, block = 30, duration = 10, charges = 4 },
}

local DEFENSE_STEP = 0.04       -- % per point of defense vs weapon skill [docs] Camelot PaperDollFrameStats.lua
local BASE_MISS, BASE_CRIT = 5, 5
local CRUSH_MIN_GAP = 15        -- crushing blows start at a 15-point skill gap: 2 % per point - 15 %
Avoidance.ORDER = { "miss", "dodge", "parry", "block", "crit", "crush" }   -- one roll, in this order; the rest is hit

local function clamp(v) return math.max(0, math.min(100, v)) end

---------------------------------------------------------------------------------------------------------------
-- Snapshot
---------------------------------------------------------------------------------------------------------------

local function StatsSecret()
    if C_Secrets and C_Secrets.ShouldUnitStatsBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldUnitStatsBeSecret)
        if ok and secret == true then return true end
    end
    return false
end

local function Num(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return Utils.SafeNumber(a), Utils.SafeNumber(b)
end

-- Off-hand item is a shield (Armor class 4, subclass 6).
local function HasShield()
    local ok, link = pcall(GetInventoryItemLink, "player", 17)
    if not ok or type(link) ~= "string" then return false end
    local okInfo, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, link)
    return okInfo and classID == 4 and subClassID == 6
end

local function HasAura(ids)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    for _, id in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and aura ~= nil then return true end
    end
    return false
end

-- Current character-sheet values, or nil while the game hides them.
function Avoidance.Read()
    if StatsSecret() then return nil end
    local base, mod = Num(UnitDefenseSkill, "player")
    local snap = {
        level = Num(UnitLevel, "player"),
        defense = base and (base + (mod or 0)),
        dodge = Num(GetDodgeChance),
        parry = Num(GetParryChance),
        block = Num(GetBlockChance),
        hasShield = HasShield(),
        known = {}, active = {},
    }
    if not (snap.level and snap.level > 0 and snap.defense and snap.dodge and snap.parry and snap.block) then return nil end
    for _, buff in ipairs(Avoidance.BUFFS) do
        snap.known[buff.key] = NS.playerClass == buff.class and Utils.KnowsAny(buff.ids)
        snap.active[buff.key] = snap.known[buff.key] and HasAura(buff.ids) or false
    end
    return snap
end

---------------------------------------------------------------------------------------------------------------
-- Math
---------------------------------------------------------------------------------------------------------------

-- snap: Read() result. opts: offset = mob level above the player (0..3), count = { [buffKey] = true }.
function Avoidance.Compute(snap, opts)
    opts = opts or {}
    local offset = opts.offset or 3
    local cap = snap.level * 5
    local skill = (snap.level + offset) * 5
    local penalty = math.max(0, skill - cap) * DEFENSE_STEP    -- sheet dodge/parry/block are vs a same-level mob

    local block, counted = 0, {}
    if snap.hasShield then
        block = snap.block
        for _, buff in ipairs(Avoidance.BUFFS) do
            if snap.active[buff.key] then block = block - buff.block end
            if snap.known[buff.key] and opts.count and opts.count[buff.key] then
                block = block + buff.block
                counted[#counted + 1] = buff
            end
        end
        block = math.max(0, block - penalty)
    end

    local raw = {
        miss = clamp(BASE_MISS + (snap.defense - skill) * DEFENSE_STEP),
        dodge = math.max(0, snap.dodge - penalty),
        parry = math.max(0, snap.parry - penalty),
        block = block,
        crit = clamp(BASE_CRIT + (skill - snap.defense) * DEFENSE_STEP),
    }
    local gap = skill - math.min(snap.defense, cap)          -- defense above the cap doesn't help here [docs]
    raw.crush = gap >= CRUSH_MIN_GAP and clamp(gap * 2 - 15) or 0

    local table_, left = {}, 100
    for _, key in ipairs(Avoidance.ORDER) do
        table_[key] = math.min(raw[key], left)
        left = left - table_[key]
    end
    table_.hit = left

    local total = raw.miss + raw.dodge + raw.parry + raw.block
    return {
        mobLevel = snap.level + offset,
        raw = raw,
        table = table_,
        total = total,
        canCrush = raw.crush > 0,
        uncrushable = raw.crush > 0 and total >= 100,
        short = math.max(0, 100 - total),
        critImmune = raw.crit <= 0,
        defenseNeeded = math.max(0, math.ceil(skill + BASE_CRIT / DEFENSE_STEP - snap.defense)),
        counted = counted,
    }
end

---------------------------------------------------------------------------------------------------------------
-- Live snapshot: re-read when stats, gear, auras or the restriction state change (out of combat)
---------------------------------------------------------------------------------------------------------------

Avoidance.last = nil        -- last snapshot read out of combat
local pending = false

function Avoidance:Update()
    pending = false
    local snap = Avoidance.Read()
    if snap then
        Avoidance.last = snap
        Avoidance.frozen = false
    elseif Avoidance.frozen then
        return              -- still hidden (combat): nothing new to show
    else
        Avoidance.frozen = true
    end
    NS:Fire("AVOIDANCE_CHANGED")
end

function Avoidance:Get()
    if not Avoidance.last or not Avoidance.frozen then
        local snap = Avoidance.Read()
        if snap then Avoidance.last, Avoidance.frozen = snap, false else Avoidance.frozen = true end
    end
    return Avoidance.last, Avoidance.frozen
end

local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() Avoidance:Update() end)
end

function Avoidance:OnEnable()
    frame:RegisterUnitEvent("UNIT_STATS", "player")
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    frame:RegisterEvent("COMBAT_RATING_UPDATE")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    frame:SetScript("OnEvent", function(_, event)
        -- Restriction "Activating" fires before the values turn secret: read right away, not after the delay.
        if event == "ADDON_RESTRICTION_STATE_CHANGED" then Avoidance:Update() else Schedule() end
    end)
    Schedule()
end

function Avoidance:OnDisable()
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
end
