-- Gear audit, step 2: sets from the Equipment Manager, purposes, verdicts per slot, intentional marks, the page.
return function(sim, t)
    local NS = sim.env.Bulwark
    local Gear = NS.GearAudit

    -- Character: level 60 warrior, defense 400, shield; Greater Stamina (929) on the bracers, a bare cloak,
    -- Lesser Block (863) on the shield.
    sim.stats = { defense = 400, defenseMod = 0, dodge = 12, parry = 11, block = 14, dodgeFromAgi = 0.05,
                  attributes = { [2] = 100 } }
    local function link(id, enchant) return "|cffffffff|Hitem:" .. id .. ":" .. (enchant or "") .. ":::::::60|h[x]|h|r" end
    sim.equipped = { [9] = link(101, 929), [15] = link(102), [17] = link(103, 863), [11] = link(104) }
    sim.itemInfo[101] = { classID = 4, subClassID = 4, equipLoc = "INVTYPE_WRIST" }
    sim.itemInfo[102] = { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK" }
    sim.itemInfo[103] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
    sim.itemInfo[104] = { classID = 4, subClassID = 0, equipLoc = "INVTYPE_FINGER" }
    sim.itemInfo[105] = { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK" }
    sim.env.C_Item.GetDetailedItemLevelInfo = function() return 60, false, 60 end

    -- Two saved sets: "Tank" (ID 0, worn) and "Fire" (ID 1): its cloak 105 is in bag 2 slot 5, enchanted with
    -- Greater Fire Resistance (2619); its bracers are the worn ones.
    local P, B = 0x00100000, 0x00200000
    local sets = {
        [0] = { name = "Tank", worn = true, locs = { [9] = P + 9, [15] = P + 15, [17] = P + 17, [11] = P + 11 },
                ids = { [9] = 101, [15] = 102, [17] = 103, [11] = 104 } },
        [1] = { name = "Fire", worn = false, locs = { [9] = P + 9, [15] = B + 2 * 256 + 5, [1] = -1 },
                ids = { [9] = 101, [15] = 105, [1] = 106 } },
    }
    sim.env.C_EquipmentSet = {
        GetEquipmentSetIDs = function() return { 1, 0 } end,
        GetEquipmentSetInfo = function(id)
            local s = sets[id]
            return s.name, 134400, id, s.worn, 0, 0, 0, 0, 0
        end,
        GetItemLocations = function(id) return sets[id].locs end,
        GetItemIDs = function(id) return sets[id].ids end,
    }
    sim.env.C_Container = { GetContainerItemLink = function(bag, slot)
        if bag == 2 and slot == 5 then return link(105, 2619) end
    end }

    -- Location decoding
    local d = Gear.DecodeLocation(B + 2 * 256 + 5)
    t.ok(d.isBags and d.bag == 2 and d.slot == 5 and not d.isPlayer, "bag location decoded")
    d = Gear.DecodeLocation(P + 17)
    t.ok(d.isPlayer and d.slot == 17, "worn location decoded")

    -- Set list: worn set first, set ID 0 handled
    local list = Gear.Sets()
    t.eq(list[1].name, "Tank", "worn set first"); t.eq(list[1].id, 0, "set ID 0 kept")
    t.eq(list[2].name, "Fire", "then the others")

    -- Avoidance set (default purpose)
    local snap = NS.Avoidance.Read()
    t.ok(snap, "snapshot")
    local a = Gear.Audit(list[1], snap, { offset = 3 })
    t.eq(a.slots[9].state, "weaker", "Greater Stamina bracers: weaker (Deflection adds avoidance)")
    t.eq(a.slots[15].state, "missing", "bare cloak: missing")
    t.eq(a.slots[17].state, "ok", "Lesser Block shield: fine (no shield enchant beats 2 % block)")
    t.eq(a.slots[11].state, nil, "ring: nothing to check")
    t.eq(a.counts.missing, 1, "one missing"); t.eq(a.counts.weaker, 1, "one weaker")

    -- Intentional mark
    Gear.Config("Tank").intentional[9] = true
    a = Gear.Audit(list[1], snap, { offset = 3 })
    t.eq(a.slots[9].state, "intentional", "marked slot")
    t.eq(a.counts.weaker, 0, "not counted as weaker")
    Gear.Config("Tank").intentional[9] = nil

    -- Threat purpose: only missing
    Gear.Config("Tank").purpose = "threat"
    a = Gear.Audit(list[1], snap, { offset = 3 })
    t.eq(a.slots[9].state, "ok", "threat set: any enchant is fine")
    t.eq(a.slots[15].state, "missing", "threat set: bare cloak still missing")
    Gear.Config("Tank").purpose = "none"
    a = Gear.Audit(list[1], snap, { offset = 3 })
    t.eq(a.counts.missing, 0, "not checked")
    Gear.Config("Tank").purpose = "avoidance"

    -- Unworn set: cloak read from the bags, missing helmet unknown
    Gear.Config("Fire").purpose = "resistance"
    a = Gear.Audit(list[2], snap, { offset = 3 })
    t.eq(a.slots[15].item.where, "bags", "cloak in the bags")
    t.eq(a.slots[15].current, 2619, "its enchant read from the bag link")
    t.eq(a.slots[15].state, "ok", "fire resistance cloak: fine in a resistance set")
    t.eq(a.slots[1].state, "unknown", "item not found")

    -- Page
    sim:Slash("/bwk")
    NS.Window:Select("utilities", "gear")
    local page
    for _, p in ipairs(NS:GetArea("utilities").pages) do if p.key == "gear" then page = p end end
    local pages = NS:GetArea("utilities").pages
    t.eq(pages[#pages].key, "options", "Options stays the last page")
    t.ok(page and page.frame and page.frame:IsShown(), "Gear page built and shown")
    t.ok(page.setName:GetText():find("Tank", 1, true), "worn set selected: " .. tostring(page.setName:GetText()))
    t.ok(page.counts:GetText():find("Missing: 1", 1, true), "counts: " .. tostring(page.counts:GetText()))
    t.ok(page.goal1:GetText():find("40 defense short", 1, true), "crit goal: " .. tostring(page.goal1:GetText()))
    page.next:Click()
    t.ok(page.setName:GetText():find("Fire", 1, true), "next set")
    t.ok(page.school:IsShown(), "resistance: school button shown")
    t.ok(page.goal1:GetText() == "", "no defense goals for a resistance set")
    page.purpose.avoidance:Click()
    t.eq(Gear.Config("Fire").purpose, "avoidance", "purpose saved per set")
    t.ok(page.goal1:GetText():find("Equip this set", 1, true), "unworn avoidance set: equip to see goals")
    page.prev:Click()
    t.ok(page.setName:GetText():find("Tank", 1, true), "back to the worn set")
    -- Right-click a flagged slot: intentional, and again: undone
    page.slots[15]:Click("RightButton")
    t.eq(Gear.Config("Tank").intentional[15], true, "right-click marks the cloak")
    page.slots[15]:Click("RightButton")
    t.eq(Gear.Config("Tank").intentional[15], nil, "right-click again unmarks it")
    page.slots[11]:Click("RightButton")
    t.eq(Gear.Config("Tank").intentional[11], nil, "nothing to mark on a ring")

    -- Entry names: "Enchant Boots - Greater Agility" -> "Greater Agility"; items keep their own name
    sim.env.C_Spell.GetSpellName = function(id) return id == 20023 and "Enchant Boots - Greater Agility" or nil end
    t.eq(Gear.EntryName({ enchant = 1887, sources = { { spell = 20023 } } }), "Greater Agility", "enchant prefix dropped")
    sim.env.C_Item.GetItemNameByID = function(id) return id == 18331 and "Arcanum of Protection" or nil end
    t.eq(Gear.EntryName({ enchant = 2545, sources = { { spell = 22846, item = 18331 } } }), "Arcanum of Protection",
        "item sources use the item name")
end
