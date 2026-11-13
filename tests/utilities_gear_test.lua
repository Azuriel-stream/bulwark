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

    -- Step 3: picker. Left-click the bracers: the summary gives way to the ranked list.
    page.slots[9]:Click("LeftButton")
    t.ok(page.picker:IsShown() and not page.summary:IsShown(), "picker replaces the summary")
    t.ok(page.picker.title:GetText():find("Wrist", 1, true), "picker title: " .. tostring(page.picker.title:GetText()))
    t.eq(page.rows[1].entry.enchant, 8214, "first row: Superior Deflection")
    t.ok(page.more:GetText():find("of", 1, true), "more rows than fit: scroll note")
    -- [in-game] a mat whose name isn't loaded showed "#12811" and stayed: the name arrives with ITEM_DATA_LOAD_RESULT
    -- (RequestLoadItemDataByID), so an open row tooltip is redrawn on it.
    local tip = sim.env.GameTooltip
    local function tipHas(text)
        for _, l in ipairs(tip._lines or {}) do if tostring(l.text):find(text, 1, true) then return true end end
        return false
    end
    page.rows[1]:GetScript("OnEnter")(page.rows[1])
    t.ok(tipHas("#14344"), "unloaded mat shows its ID first")
    local getName = sim.env.C_Item.GetItemNameByID
    sim.env.C_Item.GetItemNameByID = function(id) return id == 14344 and "Large Brilliant Shard" or getName(id) end
    sim:Fire("ITEM_DATA_LOAD_RESULT", 14344, true)
    sim:Advance(0.3)
    t.ok(tipHas("Large Brilliant Shard") and not tipHas("#14344"), "open tooltip redrawn with the loaded name")
    sim.env.C_Item.GetItemNameByID = getName
    page.rows[1]:GetScript("OnLeave")(page.rows[1])
    page.rows[1]:Click()
    t.eq(Gear.GetPick("Tank", 9), 1248665, "ticked: on the enchant list")
    t.ok(page.slots[9].pickMark:IsShown(), "gold corner on the slot")
    t.ok(page.rows[1].picked and page.rows[1].tick:IsShown(), "row shows the tick")
    page.rows[2]:Click()
    t.eq(Gear.GetPick("Tank", 9), 13931, "another row replaces the slot's pick (one per slot)")
    page.rows[2]:Click()
    t.eq(Gear.GetPick("Tank", 9), nil, "clicking the ticked row removes it")
    page.rows[1]:Click()
    -- [in-game] the paperdoll "jumped up" on every scroll: refresh re-set the model (SetUnit restarts its pose).
    local setUnits = 0
    local origSetUnit = page.model and page.model.SetUnit
    if page.model then page.model.SetUnit = function(...) setUnits = setUnits + 1; return origSetUnit(...) end end
    local wheel = page.picker:GetScript("OnMouseWheel")
    wheel(page.picker, -1)
    t.eq(page.rows[1].entry.enchant, 923, "scrolled one row down")
    wheel(page.picker, 1)
    t.eq(setUnits, 0, "scrolling the picker doesn't reload the character model")
    sim:Fire("PLAYER_EQUIPMENT_CHANGED", 9, false)
    sim:Advance(0.3)
    t.eq(setUnits, 1, "an equipment change reloads it once")
    if page.model then page.model.SetUnit = origSetUnit end
    -- Cloak: Cloak - Dodge (1 %) beats the agility enchants
    page.slots[15]:Click("LeftButton")
    t.eq(page.rows[1].entry.enchant, 2622, "cloak: Dodge first")
    page.rows[1]:Click()
    -- Shield: the current enchant is shown but can't be ticked
    page.slots[17]:Click("LeftButton")
    local cur
    for _, row in ipairs(page.rows) do if row.entry and row.entry.current then cur = row end end
    t.ok(cur and cur.name:GetText():find("(current)", 1, true), "current enchant marked")
    cur:Click()
    t.eq(Gear.GetPick("Tank", 17), nil, "current enchant can't be picked")
    page.slots[17]:Click("LeftButton")
    t.ok(not page.picker:IsShown() and page.summary:IsShown(), "clicking the open slot again closes the picker")
    t.ok(page.listCount:GetText():find("2 to do", 1, true), "summary: " .. tostring(page.listCount:GetText()))

    -- Shopping list: Superior Deflection (3 Large Brilliant Shard) + Cloak - Dodge (3 Nexus Crystal,
    -- 8 Large Brilliant Shard, 8 Guardian Stone) = 11 shards
    sim.items[14344] = 2
    local picks, mats = Gear.ShoppingList()
    t.eq(#picks, 2, "two picks")
    local shards
    for _, m in ipairs(mats) do if m.item == 14344 then shards = m end end
    t.eq(shards and shards.need, 11, "Large Brilliant Shards summed")
    NS.Window:Select("utilities", "enchantlist")
    local list
    for _, p in ipairs(NS:GetArea("utilities").pages) do if p.key == "enchantlist" then list = p end end
    t.ok(list.frame:IsShown(), "Enchant list page shown")
    t.ok(list.picks.rows[1]:IsShown() and list.picks.rows[2]:IsShown() and not list.picks.rows[3]:IsShown(), "two pick rows")
    local shardRow
    for _, row in ipairs(list.mats.rows) do if row.data and row.data.item == 14344 then shardRow = row end end
    t.eq(shardRow and shardRow.right:GetText(), "2 / 11", "have / need")

    -- Enchanting the bracers takes that pick off the mats
    sim.equipped[9] = link(101, 8214)
    picks, mats = Gear.ShoppingList()
    for _, m in ipairs(mats) do if m.item == 14344 then shards = m end end
    t.eq(shards.need, 8, "done pick no longer counted")
    t.eq(Gear.OpenPicks(), 1, "one left to do")
    list:refresh()
    t.ok(list.picks.rows[2].right:GetText() == "done" or list.picks.rows[1].right:GetText() == "done", "done marker")
    -- Remove a pick from the list page, then clear
    list.picks.rows[1].remove:Click()
    t.eq(#(Gear.ShoppingList()), 1, "removed one")
    list.clear:Click()
    t.eq(#(Gear.ShoppingList()), 0, "cleared")
    t.ok(list.empty:IsShown(), "empty note")
end
