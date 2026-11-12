local ADDON_NAME, NS = ...
local L, Utils, Avoidance = NS.L, NS.Utils, NS.Avoidance

-- Item tooltip note (option, off by default): "Total avoidance +0.64 %" when wearing the item instead of what's in
-- that slot changes it. Warrior and Paladin only, out of combat. Compared by item stats (C_Item.GetItemStats), so
-- enchants, set bonuses and "Use:" effects aren't counted. Hook as OneForAll does it on Forever [ref].
local ItemTooltip = NS:RegisterModule("ItemTooltip", "utilities")
local hooked = false

local CLASSES = { WARRIOR = true, PALADIN = true }

-- Equip location -> inventory slots it can go into.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function cfg() return NS.db.utilities end

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function Stats(link)
    if not link then return {} end
    local ok, stats = pcall(C_Item.GetItemStats, link)
    return ok and type(stats) == "table" and stats or {}
end

-- Change in total avoidance from wearing the item (best case over the slots it fits), or nil when there's nothing
-- to say (not gear, already worn, no snapshot). Second return: crit immunity after, if it flips.
function ItemTooltip.Change(link, snap, offset)
    if not (snap and type(link) == "string") then return nil end
    local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, link)
    local slots = ok and SLOTS[equipLoc]
    if not slots then return nil end
    local id = ItemID(link)
    local newStats = Stats(link)
    local base = Avoidance.Compute(snap, { offset = offset })
    local best, flip
    for _, slot in ipairs(slots) do
        local worn = GetInventoryItemLink("player", slot)
        if ItemID(worn) ~= id then
            local delta = Avoidance.AddItemStats({}, newStats, 1)
            Avoidance.AddItemStats(delta, Stats(worn), -1)
            local shield = snap.hasShield
            if slot == 17 then
                shield = classID == 4 and subClassID == 6
            elseif equipLoc == "INVTYPE_2HWEAPON" then
                Avoidance.AddItemStats(delta, Stats(GetInventoryItemLink("player", 17)), -1)   -- the off hand comes off
                shield = false
            end
            local after = Avoidance.Apply(snap, delta)
            after.hasShield = shield
            local r = Avoidance.Compute(after, { offset = offset })
            local change = r.total - base.total
            if not best or change > best then
                best = change
                flip = (r.critImmune ~= base.critImmune) and r.critImmune or nil
            end
        end
    end
    return best, flip
end

function ItemTooltip.OnTooltip(tooltip)
    if not (NS:IsAreaRunning("utilities") and cfg().tooltip and CLASSES[NS.playerClass]) then return end
    if InCombatLockdown() then return end
    local okItem, _, link = pcall(tooltip.GetItem, tooltip)
    if not okItem or Utils.IsSecret(link) then return end
    local snap = Avoidance:Get()
    local change, flip = ItemTooltip.Change(link, snap, cfg().mobOffset)
    if not change or math.abs(change) < 0.005 then return end
    local text = string.format(L["TT_AVOIDANCE"], string.format("%+.2f", change))
    if flip == true then text = text .. "  " .. L["TT_CRIT_IMMUNE"]
    elseif flip == false then text = text .. "  " .. L["TT_CRIT_LOST"] end
    if change > 0 then tooltip:AddLine(text, 0.30, 0.85, 0.45) else tooltip:AddLine(text, 1.00, 0.45, 0.30) end
end

-- The hook can't be removed again, so it's installed once (the first time the area starts) and checks the option.
function ItemTooltip:OnEnable()
    if hooked then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
    hooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip or tooltip == ItemRefTooltip then
            local ok, err = pcall(ItemTooltip.OnTooltip, tooltip)
            if not ok then NS:Debug("ItemTooltip: %s", tostring(err)) end
        end
    end)
end
