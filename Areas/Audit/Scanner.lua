local ADDON_NAME, NS = ...
local Utils, D, L = NS.Utils, NS.AuditData, NS.L

-- Out of combat, decides WHAT the tiles show: which tiles (checklist), in which order, and what clicking a missing
-- tile does. Whether each buff is up, and its timer, is drawn live by Blizzard aura slots on the tiles (Bar.lua),
-- which keeps working in combat. Forever hides aura data from addons in combat, so planning only runs out of combat
-- and the layout freezes during fights (kb/restrictions.md). (from TankAuditForever Modules/Scanner.lua)
local Scanner = NS:RegisterModule("AuditScanner", "audit")

local frame = CreateFrame("Frame", "Bulwark_AuditScannerFrame")
local ticker = nil
local queued = false

local function cfg() return NS.db.audit end

-- plan.tiles = ordered items: { tileKey, key, label, spellId, messageKey, watchIds, ids, warn, expiresAt,
--                               action = { type = "spell"|"request"|"bags", spell, unit } }
-- plan.salvation = show the Salvation (cancel) slot
-- plan.dispelActions = { [dispelType] = action } for the debuff tiles to show
Scanner.plan = { tiles = {} }

local function IsStanceActive(spellID)
    for i = 1, GetNumShapeshiftForms() do
        local _, active, _, formSpellID = GetShapeshiftFormInfo(i)
        if active and formSpellID == spellID then return true end
    end
    return false
end

local function MergeIds(a, b)
    local set = Utils.ToSet(a)
    for _, id in ipairs(b or {}) do set[id] = true end
    return set
end

-- Action for a buff the player may be able to cast on themselves.
local function CastOrRequest(ids, castId)
    if castId and Utils.IsKnown(castId) then
        return { type = "spell", spell = Utils.SpellName(castId), unit = "player" }
    end
    for _, id in ipairs(ids or {}) do
        if Utils.IsKnown(id) then
            return { type = "spell", spell = Utils.SpellName(id), unit = "player" }
        end
    end
    return { type = "request" }
end

local SELF_WARN, GROUP_WARN, CONSUMABLE_WARN = 15, 60, 60

-- item.expiresAt: nil = missing, 0 = up with no known expiry (never "expiring"), otherwise GetTime()-based expiry.
local function ExpiryOf(aura)
    if not aura then return nil end
    local expires = aura.expirationTime
    return (expires and expires > 0) and expires or 0
end

local function FindAura(byId, idSet)
    for id in pairs(idSet) do
        if byId[id] then return byId[id] end
    end
end

local function SpellItem(tileKey, key, ids, labelKey, warn, byId, extraIds)
    local idSet = MergeIds(ids, extraIds)
    return {
        tileKey = tileKey,
        key = key,
        label = (labelKey and L[labelKey]) or Utils.SpellName(ids[1]) or key,
        spellId = ids[1],
        messageKey = key,
        ids = idSet,
        warn = warn,
        expiresAt = ExpiryOf(FindAura(byId, idSet)),
    }
end

-- Main-hand temporary enchant (sharpening stone, oil...). Returns hasEnchant, secondsLeft.
-- timeLeft is assumed to be milliseconds like the legacy API [unverified: check /bwk audit dump].
local function MainHandEnchant()
    local slot = Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
    local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, slot)
    if not ok or type(enchants) ~= "table" then return false, 0 end
    for _, info in ipairs(enchants) do
        if info.hasEnchant and not Utils.IsSecret(info.timeLeft) then
            return true, (info.timeLeft or 0) / 1000
        end
    end
    return false, 0
end

-- Dispel types worth showing, with the click action for each: cast your own dispel if you know one, otherwise ask
-- the group (only if someone in it has the class AND level to remove that type).
local function DispelActions(class, Roster)
    local actions = {}
    for dtype, requirements in pairs(D.DISPEL_LEVELS) do
        for _, id in ipairs((D.PLAYER_DISPELS[class] or {})[dtype] or {}) do
            if Utils.IsKnown(id) then
                actions[dtype] = { type = "spell", spell = Utils.SpellName(id), unit = "player" }
                break
            end
        end
        if not actions[dtype] and Roster:OthersCanDispel(requirements) then
            actions[dtype] = { type = "request" }
        end
    end
    return actions
end

-- Blessing priority for the player's class (with N paladins in the group, the top N are expected).
function Scanner.BlessingPriority()
    local all = cfg().blessingPriority
    local class = NS.playerClass or "WARRIOR"
    if not all[class] then all[class] = NS.CopyTable(NS.DefaultConfig.audit.blessingPriority.WARRIOR) end
    return all[class]
end

function Scanner.MoveBlessing(index, direction)
    local list = Scanner.BlessingPriority()
    local target = index + direction
    if target < 1 or target > #list then return end
    list[index], list[target] = list[target], list[index]
end

local SLOT_COUNT = 18
local function GearTile(key, detail)
    return { tileKey = "GEAR:" .. key, key = key, label = L["GEAR_" .. key], detail = detail, alwaysShow = true }
end

-- Gear warning tiles (only what's wrong):
--   defense skill 2+ points below level x 5 (groups only: it lags after every level-up while you quest; the last point
--   before the cap can take 1,000+ hits and is worth 0.04 % per avoidance stat, so cap - 1 counts as maxed),
--   tanking (Defensive Stance / Righteous Fury) without a shield,
--   an equipped item at or below c.durabilityWarn % durability.
function Scanner.GearWarnings(c, solo, byId)
    local out = {}
    local level = Utils.SafeNumber(UnitLevel("player"))
    if c.checkDefenseSkill and not solo and level then
        local ok, base, mod = pcall(UnitDefenseSkill, "player")
        base, mod = ok and Utils.SafeNumber(base), ok and Utils.SafeNumber(mod, 0) or 0
        local cap = level * 5
        if base and base < cap - 1 then
            local detail = string.format(L["GEAR_DEFENSE_SKILL_DETAIL"], base, cap)
            if base + mod < cap then detail = detail .. " " .. L["GEAR_DEFENSE_SKILL_CRUSH"] end
            out[#out + 1] = GearTile("DEFENSE_SKILL", detail)
        end
    end
    if c.checkShield then
        local class = NS.playerClass
        local tanking = (class == "WARRIOR" and IsStanceActive(71)) or (class == "PALADIN" and byId and byId[25780] ~= nil)
        if tanking and not Utils.HasShield() then
            out[#out + 1] = GearTile("NO_SHIELD", L["GEAR_NO_SHIELD_DETAIL"])
        end
    end
    if c.checkDurability then
        local lowest, lowestSlot
        for slot = 1, SLOT_COUNT do
            local ok, cur, max = pcall(GetInventoryItemDurability, slot)
            cur, max = ok and Utils.SafeNumber(cur), ok and Utils.SafeNumber(max)
            if cur and max and max > 0 then
                local pct = cur / max * 100
                if not lowest or pct < lowest then lowest, lowestSlot = pct, slot end
            end
        end
        if lowest and lowest <= (c.durabilityWarn or 25) then
            local link = GetInventoryItemLink("player", lowestSlot)
            local name = type(link) == "string" and link:match("%[(.-)%]") or "?"
            out[#out + 1] = GearTile("DURABILITY", string.format(L["GEAR_DURABILITY_DETAIL"], name, lowest))
        end
    end
    return out
end

-- Every tile that applies right now (the bar shows only missing/expiring ones; the rest wait invisibly so they can
-- fade in during combat when they approach expiry).
function Scanner:BuildPlan(helpful)
    local Roster = NS.AuditRoster
    Roster:Update()
    local c = cfg()
    local class = NS.playerClass
    local solo = Roster.isSolo
    local tiles = {}

    local byId = {}
    for _, aura in ipairs(helpful or {}) do byId[aura.spellId] = byId[aura.spellId] or aura end

    -- 1. Self buffs (always, solo too) and stance (groups only, when not in it)
    if c.checkSelf then
        for _, def in ipairs(D.SELF[class] or {}) do
            if def.stance then
                if not (def.skipSolo and solo) and Utils.IsKnown(def.stance) and not IsStanceActive(def.stance) then
                    local item = SpellItem("SELF:" .. def.key, def.key, { def.stance }, nil, SELF_WARN, {})
                    item.action = { type = "spell", spell = Utils.SpellName(def.stance) }
                    item.alwaysShow = true -- a prompt: only planned while you're not in the stance
                    tiles[#tiles + 1] = item
                end
            elseif not def.requireKnown or Utils.KnowsAny(def.ids) then
                local item = SpellItem("SELF:" .. def.key, def.key, def.ids, nil, def.warn or SELF_WARN, byId)
                item.action = CastOrRequest(def.ids)
                item.ownCast = def.alert -- SelfAlert keeps expiresAt current from your own casts, even in combat
                tiles[#tiles + 1] = item
            end
        end
    end

    if not solo then
        -- 2. Group buffs from classes present, then paladin blessings by priority
        if c.checkGroup then
            for _, def in ipairs(D.GROUP) do
                if Roster:Count(def.provider, def.subgroupOnly) > 0 and not (def.skipFor and def.skipFor[class]) then
                    local item = SpellItem("GROUP:" .. def.key, def.key, def.ids, def.label, GROUP_WARN, byId, def.greater)
                    item.action = CastOrRequest(def.ids, def.castId)
                    item.watchIds = item.ids
                    tiles[#tiles + 1] = item
                end
            end
            local priority = Scanner.BlessingPriority()
            for i = 1, math.min(Roster:Count("PALADIN"), #priority) do
                local def = D.BLESSINGS[priority[i]]
                if def then
                    local item = SpellItem("BLESSING:" .. priority[i], priority[i], def.ids, nil, GROUP_WARN, byId, def.greater)
                    item.action = CastOrRequest(def.ids)
                    item.watchIds = item.ids
                    tiles[#tiles + 1] = item
                end
            end
        end
    end

    -- 3. Consumables: in a group, solo, or both (user's choice)
    if c.checkConsumables and (solo and c.consumablesSolo or not solo and c.consumablesInGroup) then
        local function Consumable(key, ids)
            local idSet = Utils.ToSet(ids)
            local item = { tileKey = "CONS:" .. key, key = key, label = L[key], action = { type = "bags" },
                           ids = idSet, warn = CONSUMABLE_WARN, expiresAt = ExpiryOf(FindAura(byId, idSet)) }
            tiles[#tiles + 1] = item
            return item
        end
        local fed = Consumable("WELL_FED", D.WELL_FED)
        if fed.expiresAt == nil then
            for _, aura in ipairs(helpful or {}) do
                if aura.name == L["WELL_FED"] then fed.expiresAt = ExpiryOf(aura) break end
            end
        end
        if c.consumableLevel == 2 then Consumable("ELIXIR", D.ELIXIRS) elseif c.consumableLevel == 3 then Consumable("FLASK", D.FLASKS) end
        local weapon = Consumable("WEAPON_BUFF", {})
        local hasEnchant, secondsLeft = MainHandEnchant()
        if hasEnchant then
            weapon.expiresAt = secondsLeft > 0 and (GetTime() + secondsLeft) or 0
        end
    end

    -- 4. Healthstone: only when a warlock (other than you) is around and you carry none
    if c.checkHealthstone and Roster:CountOthers("WARLOCK") > 0 then
        local carried = 0
        for _, itemID in ipairs(D.HEALTHSTONES) do
            carried = carried + (C_Item.GetItemCount(itemID) or 0)
        end
        if carried == 0 then
            tiles[#tiles + 1] = { tileKey = "HEALTHSTONE", key = "HEALTHSTONE", label = L["HEALTHSTONE"],
                messageKey = "HEALTHSTONE", action = { type = "request" }, alwaysShow = true }
        end
    end

    -- 5. Tank gear (user 2026-11-12: these warnings are Audit tiles). Prompts: shown while planned.
    for _, item in ipairs(Scanner.GearWarnings(c, solo, byId)) do tiles[#tiles + 1] = item end

    return {
        tiles = tiles,
        salvation = c.checkUnwanted,
        dispelActions = c.checkDebuffs and DispelActions(class, Roster) or {},
    }
end

function Scanner:Scan()
    if not NS:IsAreaRunning("audit") or not NS.AuditBar:IsBuilt() or InCombatLockdown() then return end
    -- Gratitude needs the (readable, out-of-combat) aura list
    local helpful = {}
    if not Utils.ForEachAura("player", "HELPFUL", function(aura) helpful[#helpful + 1] = aura end) then
        return -- restricted right now; keep the current plan
    end
    self.plan = self:BuildPlan(helpful)
    NS.AuditGratitude:Check(helpful)
    NS.AuditBar:Apply(self.plan)
end

-- Coalesce bursts of events into one scan.
function Scanner:Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        Scanner:Scan()
    end)
end

-- /bwk audit dump: everything needed to verify the spell IDs in Data.lua.
function Scanner:Dump()
    if InCombatLockdown() then
        NS:Print(L["AUDIT_IN_COMBAT_LATER"])
        return
    end
    NS:Print(L["AUDIT_DUMP_HEADER"])
    local now = GetTime()
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        Utils.ForEachAura("player", filter, function(a)
            local source = a.sourceUnit and Utils.GetUnitFullName(a.sourceUnit) or "-"
            local left = (a.expirationTime and a.expirationTime > 0) and Utils.FormatTime(a.expirationTime - now) or "-"
            print(string.format("  %s %d  %s  src:%s  %s%s", filter == "HARMFUL" and "|cffFF4444DEBUFF|r" or "buff",
                a.spellId, tostring(a.name), source, left, a.dispelName and ("  type:" .. a.dispelName) or ""))
        end)
    end
    local slot = Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
    local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, slot)
    if ok and type(enchants) == "table" then
        for _, e in ipairs(enchants) do
            print(string.format("  weapon enchant: has=%s timeLeft(raw)=%s enchantID=%s", tostring(e.hasEnchant),
                tostring(e.timeLeft), tostring(e.enchantID)))
        end
    end
    for i = 1, GetNumShapeshiftForms() do
        local _, active, _, spellID = GetShapeshiftFormInfo(i)
        print(string.format("  stance %d: spellID=%s active=%s", i, tostring(spellID), tostring(active)))
    end
end

local function OnEvent()
    if not InCombatLockdown() then Scanner:Queue() end
end

function Scanner:OnEnable()
    if not NS.AuditBar:IsBuilt() then return end
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
        "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", OnEvent)
    if ticker then ticker:Cancel() end
    -- Periodic replan (stance, bags, roster changes without events)
    ticker = C_Timer.NewTicker(3, function()
        if not InCombatLockdown() then Scanner:Scan() end
    end)
    self:Queue()
end

function Scanner:OnDisable()
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    if ticker then ticker:Cancel(); ticker = nil end
    self.plan = { tiles = {} }
end
