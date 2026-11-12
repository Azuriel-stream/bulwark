local ADDON_NAME, NS = ...
local Enchants = NS.Enchants

-- Gear audit (kb/addons/Bulwark-Utilities.md "Idea: Gear audit"): which gear to check (a saved Equipment Manager set,
-- or what is worn when it matches no set), the purpose the user gave that set, and a verdict per slot.
-- Purposes: avoidance = missing + weaker (ranked by avoidance gain, not Best-in-Slot); threat and resistance =
-- missing only (a stamina set counts as threat: user, 2026-11-12); none = not checked.
local Gear = {}
NS.GearAudit = Gear

Gear.WORN = "@worn"     -- settings key of "current gear" (no saved set worn)
Gear.PURPOSES = { "avoidance", "threat", "resistance", "none" }
Gear.SCHOOLS = { "fire", "nature", "frost", "shadow", "arcane" }
Gear.SCHOOL_INDEX = { fire = 2, nature = 3, frost = 4, shadow = 5, arcane = 6 }   -- UnitResistance index
-- Paperdoll: left column, right column (equipment slot IDs). Shirt, tabard and ranged are left out: nothing for a tank.
Gear.LEFT = { 1, 2, 3, 15, 5, 9, 16, 17 }
Gear.RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }

NS.DefaultCharConfig.gear = {
    sets = {},          -- [set name or Gear.WORN] = { purpose =, school =, intentional = { [slot] = true } }
}

-- Equipment set item locations [docs] Blizzard_FrameXMLBase/Constants.lua (EquipmentManager_GetLocationData).
local LOC_EMPTY, LOC_IGNORED, LOC_MISSING = 0, 1, -1
local LOC_PLAYER, LOC_BAGS, LOC_BANK = 0x00100000, 0x00200000, 0x00400000
local BAG_SHIFT = 8

function Gear.DecodeLocation(loc)
    local d = { isPlayer = bit.band(loc, LOC_PLAYER) ~= 0, isBags = bit.band(loc, LOC_BAGS) ~= 0,
                isBank = bit.band(loc, LOC_BANK) ~= 0 }
    local slot = bit.band(loc, 0x000FFFFF)
    if d.isBags then
        d.bag = bit.rshift(slot, BAG_SHIFT)
        slot = slot - bit.lshift(d.bag, BAG_SHIFT)
        if d.isBank then   -- bank bags come after the equipped bags
            d.bag = d.bag + (ITEM_INVENTORY_BANK_BAG_OFFSET or NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4)
        end
    end
    d.slot = slot
    return d
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
end

-- Choices for the set selector: saved sets (worn first, then by name); "current gear" first when no saved set is worn.
function Gear.Sets()
    local list = {}
    local api = C_EquipmentSet
    for _, id in ipairs(api and Call(api.GetEquipmentSetIDs) or {}) do
        local name, icon, _, isEquipped = Call(api.GetEquipmentSetInfo, id)
        if type(name) == "string" and name ~= "" then
            list[#list + 1] = { id = id, key = name, name = name, icon = icon, worn = isEquipped == true }
        end
    end
    table.sort(list, function(a, b)
        if a.worn ~= b.worn then return a.worn end
        return a.name < b.name
    end)
    if not (list[1] and list[1].worn) then
        table.insert(list, 1, { key = Gear.WORN, worn = true, current = true })
    end
    return list
end

function Gear.Config(key)
    local sets = NS.char.gear.sets
    local c = sets[key]
    if type(c) ~= "table" then
        c = {}
        sets[key] = c
    end
    c.purpose = c.purpose or "avoidance"
    c.school = c.school or "fire"
    c.intentional = c.intentional or {}
    return c
end

-- Item per slot: { link, itemID, where = "worn" | "bags" | "bank" | "missing" }. Empty and ignored slots: nil.
-- link is nil when the item can't be read (in the bank while it is closed, or not found).
function Gear.Items(set)
    local items = {}
    if set.current then
        for slot = 1, 19 do
            local link = Call(GetInventoryItemLink, "player", slot)
            if link then items[slot] = { link = link, where = "worn" } end
        end
        return items
    end
    local api = C_EquipmentSet
    local locs = Call(api.GetItemLocations, set.id) or {}
    local ids = Call(api.GetItemIDs, set.id) or {}
    for slot = 1, 19 do
        local loc = locs[slot]
        if type(loc) == "number" and loc ~= LOC_EMPTY and loc ~= LOC_IGNORED then
            local item = { itemID = ids[slot] }
            if loc == LOC_MISSING then
                item.where = "missing"
            else
                local d = Gear.DecodeLocation(loc)
                if d.isBags then
                    item.link = C_Container and Call(C_Container.GetContainerItemLink, d.bag, d.slot)
                    item.where = d.isBank and "bank" or "bags"
                elseif d.isPlayer then
                    item.link = Call(GetInventoryItemLink, "player", d.slot)
                    item.where = "worn"
                else
                    item.link = Call(GetInventoryItemLink, "player", d.slot)    -- bank slot: readable while open
                    item.where = "bank"
                end
            end
            items[slot] = item
        end
    end
    return items
end

-- What Enchants.Fits needs to know about an item.
function Gear.ItemInfo(link)
    local _, _, _, equipLoc, icon, classID, subClassID = Call(C_Item.GetItemInfoInstant, link)
    local ilvl = Call(C_Item.GetDetailedItemLevelInfo, link)
    return { classID = classID, subClassID = subClassID, equipLoc = equipLoc, icon = icon,
             ilvl = type(ilvl) == "number" and ilvl or nil }
end

-- Audit of one set: { [slot] = { item, info, current, state, list } } plus counts.
-- state: "missing", "weaker", "intentional" (flagged, but the user marked it), "unknown" (can't read the item),
-- "ok" (fine) or nil (nothing to check). list = enchants that fit, ranked by avoidance gain.
function Gear.Audit(set, snap, opts)
    local cfg = Gear.Config(set.key)
    local result = { slots = {}, counts = { missing = 0, weaker = 0, intentional = 0, unknown = 0 } }
    for slot, item in pairs(Gear.Items(set)) do
        local r = { item = item }
        result.slots[slot] = r
        if cfg.purpose == "none" then
            -- not checked
        elseif not item.link then
            r.state = "unknown"
        elseif snap then
            r.info = Gear.ItemInfo(item.link)
            r.current = Enchants.FromLink(item.link)
            local state, list = Enchants.Verdict(snap, slot, r.info, r.current, opts)
            if state == "weaker" and cfg.purpose ~= "avoidance" then state = nil end
            if state and cfg.intentional[slot] then state = "intentional" end
            r.state = state or (#list > 0 and "ok" or nil)
            r.list = list
        end
        if r.state and result.counts[r.state] then result.counts[r.state] = result.counts[r.state] + 1 end
    end
    return result
end

-- Display name of a ranked entry: the item that applies it, else the enchanting spell.
function Gear.EntryName(entry)
    local src = entry.sources[1]
    local name = src.item and C_Item.GetItemNameByID and Call(C_Item.GetItemNameByID, src.item)
    if not name and C_Spell and C_Spell.GetSpellName then name = Call(C_Spell.GetSpellName, src.spell) end
    return name or ("#" .. tostring(entry.enchant))
end
