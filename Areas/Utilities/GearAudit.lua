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
    picks = {},         -- ["<set key>:<slot>"] = { set =, slot =, spell = source spell } (the enchant list)
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

-- Resistance purpose: entries with the most resistance of the set's school first, then by avoidance.
function Gear.SortFor(list, purpose, school)
    if purpose ~= "resistance" then return list end
    local function res(e) return Enchants.Stats(e.enchant)[school] or 0 end
    table.sort(list, function(a, b)
        if res(a) ~= res(b) then return res(a) > res(b) end
        if math.abs(a.gain - b.gain) > 0.005 then return a.gain > b.gain end
        return a.enchant < b.enchant
    end)
    return list
end

---------------------------------------------------------------------------------------------------------------
-- Enchant list: picks (one enchant per slot per set) and the mats they need
---------------------------------------------------------------------------------------------------------------

local bySpell
function Gear.SourceBySpell(spell)
    if not bySpell then
        bySpell = {}
        for _, src in ipairs(NS.EnchantData and NS.EnchantData.sources or {}) do
            bySpell[src.spell] = bySpell[src.spell] or src
        end
    end
    return bySpell[spell]
end

local function PickKey(setKey, slot) return setKey .. ":" .. slot end

function Gear.GetPick(setKey, slot)
    local p = NS.char.gear.picks[PickKey(setKey, slot)]
    return p and p.spell
end

-- spell = source spell to pick, nil to remove the pick for that slot.
function Gear.SetPick(setKey, slot, spell)
    NS.char.gear.picks[PickKey(setKey, slot)] = spell and { set = setKey, slot = slot, spell = spell } or nil
    NS:Fire("GEAR_PICKS_CHANGED")
end

function Gear.ClearPicks()
    wipe(NS.char.gear.picks)
    NS:Fire("GEAR_PICKS_CHANGED")
end

-- Picks with their state, and the summed mats of the ones still to do.
-- picks = { { key, set (key), slot, src, done } } (done = the item in that slot already has the enchant: not counted)
-- mats = { { item, need } } in Gear.SortMats order; item sources count the item itself once.
function Gear.ShoppingList()
    local setByKey = {}
    for _, s in ipairs(Gear.Sets()) do setByKey[s.key] = s end
    local itemsBySet = {}
    local picks, need = {}, {}
    for key, p in pairs(NS.char.gear.picks) do
        local src = type(p) == "table" and Gear.SourceBySpell(p.spell)
        if src then
            local entry = { key = key, set = p.set, slot = p.slot, src = src }
            local set = setByKey[p.set]
            if set then
                itemsBySet[p.set] = itemsBySet[p.set] or Gear.Items(set)
                local item = itemsBySet[p.set][p.slot]
                entry.done = item and item.link and Enchants.FromLink(item.link) == src.enchant or false
            end
            picks[#picks + 1] = entry
            if not entry.done then
                if src.item then
                    need[src.item] = (need[src.item] or 0) + 1
                else
                    for i = 1, #(src.reagents or {}), 2 do
                        local id, n = src.reagents[i], src.reagents[i + 1]
                        need[id] = (need[id] or 0) + n
                    end
                end
            end
        end
    end
    table.sort(picks, function(a, b)
        if a.set ~= b.set then return a.set < b.set end
        return a.slot < b.slot
    end)
    local mats = {}
    for id, n in pairs(need) do mats[#mats + 1] = { item = id, need = n } end
    return picks, Gear.SortMats(mats)
end

-- Item quality (0 poor .. 4 epic): generated data first (no item cache needed), else the client.
function Gear.Quality(itemID)
    local q = NS.EnchantData and NS.EnchantData.quality and NS.EnchantData.quality[itemID]
    if not q and C_Item.GetItemQualityByID then q = Call(C_Item.GetItemQualityByID, itemID) end
    return type(q) == "number" and q or 1
end

-- One order for the Enchant list and the tracker (user, 2026-11-12): best quality first (epic .. common), then name.
function Gear.SortMats(mats)
    for _, m in ipairs(mats) do
        m.quality = Gear.Quality(m.item)
        m.name = Gear.ItemName(m.item) or ("#" .. m.item)
    end
    table.sort(mats, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        return a.item < b.item
    end)
    return mats
end

-- Picks still to do (the slot doesn't have the enchant yet).
function Gear.OpenPicks()
    local n = 0
    for _, p in ipairs((Gear.ShoppingList())) do
        if not p.done then n = n + 1 end
    end
    return n
end

-- How many of an item the player has (bags + bank).
function Gear.Have(itemID)
    return Call(C_Item.GetItemCount, itemID, true) or 0
end

-- Item name, or nil while the client hasn't loaded it (asks for it: ITEM_DATA_LOAD_RESULT follows; listeners also
-- take GET_ITEM_INFO_RECEIVED, which GetItemInfo-style lookups fire).
function Gear.ItemName(itemID)
    local name = C_Item.GetItemNameByID and Call(C_Item.GetItemNameByID, itemID)
    if not name and C_Item.RequestLoadItemDataByID then Call(C_Item.RequestLoadItemDataByID, itemID) end
    return name
end

-- Display name of a ranked entry: the item that applies it, else the enchanting spell.
function Gear.EntryName(entry)
    local src = entry.sources[1]
    local name = src.item and C_Item.GetItemNameByID and Call(C_Item.GetItemNameByID, src.item)
    if not name and C_Spell and C_Spell.GetSpellName then
        name = Call(C_Spell.GetSpellName, src.spell)
        -- "Enchant Boots - Greater Agility" -> "Greater Agility": the slot is already known (enUS spell names)
        if type(name) == "string" then name = name:gsub("^Enchant [^%-]+ %- ", "") end
    end
    return name or ("#" .. tostring(entry.enchant))
end
