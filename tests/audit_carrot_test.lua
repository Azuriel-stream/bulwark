-- Carrot on a Stick (Areas/Audit/Carrot.lua): green tile when mounted with it in the bags (click = equip into the
-- chosen slot, the old trinket remembered), orange tile a few seconds after dismounting with it on (click = list of
-- bag trinkets, the old one first), nothing in combat / dead / on a taxi / option off; equips checked afterwards.
return function(sim, t)
    local CARROT, HOJ, WATCH, CHARM, BREAD = 11122, 11815, 2820, 1404, 4540

    local function setup(s)
        s.itemNames[CARROT] = "Carrot on a Stick"
        s.itemNames[HOJ] = "Hand of Justice"
        s.itemNames[WATCH] = "Nifty Stopwatch"
        s.itemNames[CHARM] = "Alarm-O-Bot"   -- sorts before the remembered ones: the sort must put those first
        s.itemNames[BREAD] = "Tough Hunk of Bread"
        for _, id in ipairs({ CARROT, HOJ, WATCH, CHARM }) do
            s.itemInfo[id] = { classID = 4, subClassID = 0, equipLoc = "INVTYPE_TRINKET" }
        end
        s.itemInfo[BREAD] = { classID = 0, subClassID = 5, equipLoc = "" }
        s.equipped[13] = "|cff0070dd|Hitem:" .. HOJ .. "::::::::|h[Hand of Justice]|h|r"
        s.equipped[14] = "|cff1eff00|Hitem:" .. WATCH .. "::::::::|h[Nifty Stopwatch]|h|r"
        s.bags[0] = { size = 16, [2] = BREAD, [3] = CARROT, [7] = CHARM }
    end
    local function frames(w) return w.env.Bulwark.AuditCarrot:GetFrames() end
    local function shown(w)
        local frame, tile = frames(w)
        return frame:IsShown() and tile.state or nil
    end
    local function mount(w, on)
        w.mounted = on
        w:Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
        w:Advance(1)
    end
    local function slotID(w, slot) return w.env.GetInventoryItemID("player", slot) end
    local function printed(w, text)
        for _, line in ipairs(w.output) do
            if tostring(line):find(text, 1, true) then return true end
        end
        return false
    end

    local w = t.fresh(setup)
    w:Advance(1)
    t.eq(shown(w), nil, "on foot, Carrot in the bags (not worn): no tile")

    ------------------------------------------------------------------ mounted: green tile, click puts it on
    mount(w, true)
    t.eq(shown(w), "puton", "mounted with the Carrot in the bags: put-on tile")
    local _, tile = frames(w)
    tile:Click()
    w:Advance(2)
    t.eq(slotID(w, 14), CARROT, "Carrot in the default slot 14")
    t.eq(w.env.BulwarkCharDB.carrotPrev.itemID, WATCH, "the replaced trinket is remembered")
    t.eq(shown(w), nil, "mounted and wearing it: no tile")

    ------------------------------------------------------------------ dismount: the swap tile waits a few seconds
    mount(w, false)
    t.eq(shown(w), nil, "just dismounted: no tile yet")
    w:Advance(2)
    t.eq(shown(w), nil, "3 s on foot: still waiting")
    w:Advance(2)
    t.eq(shown(w), "swap", "after a few seconds on foot with the Carrot on: swap tile")

    -- a quick hop off and back on never shows it
    mount(w, true)
    t.eq(shown(w), nil, "mounted again: swap tile gone (wearing it)")
    mount(w, false)

    -- the list: remembered trinket first, then the others; no Carrot, no worn trinket, no bread
    local options = w.env.Bulwark.AuditCarrot.SwapOptions()
    t.ok(options[1].header, "list starts with its header")
    t.eq(options[2].key, WATCH, "the trinket the Carrot replaced comes first")
    t.ok(options[2].label:find("was here", 1, true), "and says so")
    t.eq(options[3].key, CHARM, "then the other bag trinkets")
    t.eq(#options, 3, "no Carrot, no worn trinket, no food in the list")

    w:Advance(5)
    t.eq(shown(w), "swap", "swap tile back after the wait")
    tile:Click()
    t.ok(w.env.Bulwark.Kit.IsListOpen(tile), "click opens the trinket list")
    local picked = false
    for _, row in ipairs(w.env.Bulwark_DropdownList.rows) do
        if row.option and row.option.key == WATCH and row:IsShown() then row:Click(); picked = true end
    end
    t.ok(picked, "list row for the old trinket")
    w:Advance(2)
    t.eq(slotID(w, 14), WATCH, "old trinket back in the Carrot's slot")
    t.eq(shown(w), nil, "Carrot off: no tile")

    ------------------------------------------------------------------ blockers: combat, taxi, dead, option
    mount(w, true)
    t.eq(shown(w), "puton", "mounted again: put-on tile")
    w:EnterCombat()
    t.eq(shown(w), nil, "combat hides it at once")
    w:Fire("BAG_UPDATE_DELAYED"); w:Advance(1)
    t.eq(shown(w), nil, "a refresh in combat keeps it hidden")
    local calls = #w.equipCalls
    w.env.Bulwark.AuditCarrot.PutOn()
    t.eq(#w.equipCalls, calls, "no equip attempt in combat")
    t.ok(printed(w, "can't be changed in combat"), "says why")
    w:LeaveCombat()
    w:Advance(1)
    t.eq(shown(w), "puton", "back after combat")

    w.env.BulwarkDB.audit.carrot = false
    w.env.Bulwark.AuditCarrot:Changed(); w:Advance(1)
    t.eq(shown(w), nil, "option off: no tile")
    w.env.BulwarkDB.audit.carrot = true

    -- slot 13 chosen
    w.env.BulwarkDB.audit.carrotSlot = 13
    w.env.Bulwark.AuditCarrot:Changed(); w:Advance(1)
    tile:Click()
    w:Advance(2)
    t.eq(slotID(w, 13), CARROT, "Carrot into slot 13 when chosen")
    t.eq(w.env.BulwarkCharDB.carrotPrev.itemID, HOJ, "Hand of Justice remembered")

    -- flight path: no tile on the taxi; after landing the swap tile still waits
    w.mounted, w.onTaxi = false, true
    w:Fire("PLAYER_CONTROL_LOST"); w:Advance(10)
    t.eq(shown(w), nil, "on a flight path: no tile")
    w.onTaxi = false
    w:Fire("PLAYER_CONTROL_GAINED"); w:Advance(1)
    t.eq(shown(w), nil, "just landed: waiting")
    w:Advance(5)
    t.eq(shown(w), "swap", "landed a few seconds ago: swap tile")

    ------------------------------------------------------------------ a failed equip is reported
    w.equipItem = function() end
    tile:Click()   -- opens the list
    local options2 = w.env.Bulwark.AuditCarrot.SwapOptions()
    t.eq(options2[2].key, HOJ, "the remembered trinket first again")
    w.env.Bulwark.Kit.CloseList()
    for _, row in ipairs(w.env.Bulwark_DropdownList.rows) do
        if row.option and row.option.key == HOJ then row:Click() end
    end
    w:Advance(2)
    t.ok(printed(w, "Couldn't put Hand of Justice into trinket slot 13"), "failed equip printed")

    ------------------------------------------------------------------ no Carrot at all: never a tile; window preview
    local n = t.fresh(function(s) setup(s); s.bags[0][3] = nil end)
    n.mounted = true
    n:Fire("PLAYER_MOUNT_DISPLAY_CHANGED"); n:Advance(1)
    t.eq(shown(n), nil, "mounted without a Carrot: no tile")
    n:Slash("/bwk audit")
    n:Advance(1)
    t.eq(shown(n), "puton", "Audit tab open: sample tile")
    n:Slash("/bwk")
    n:Advance(1)
    t.eq(shown(n), nil, "window closed: sample gone")
end
