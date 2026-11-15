-- Briefing step 4 (kb/addons/Bulwark-Briefing.md): your priority and note per mob cast, on Marking > Briefing.
-- Saved by mob name: BulwarkDB.marking.briefing.overrides[mob][spellID] = { prio, note }.
local H = require("mark_helpers")
local RFC = 389

local function setup(s)
    H.install(s)
    s.zone = "Ragefire Chasm"
    s.env.IsInInstance = function() return true, "party" end
    s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, RFC, 5, nil, false end
    s.known[72] = true
    s.equipped[17] = "|cffffffff|Hitem:4975::::::::|h[Vigilant Buckler]|h|r"
    s.itemInfo[4975] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
    s.spells[11986], s.spells[9532], s.spells[72], s.spells[11976] = "Healing Wave", "Lightning Bolt", "Shield Bash", "Strike"
end

return function(_, t)
    local sim = t.fresh(setup)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local B = MK.Briefing

    -- Rows: mobs with their casts; passive-only mobs left out; bosses last.
    local rows = B.AbilityRows(RFC)
    t.eq(rows[1].mob, "Earthborer", "first mob (by name)")
    t.ok(rows[1].spell == nil and rows[2].spell ~= nil, "a mob row, then its casts")
    local mobsListed, lastBoss, sawTrashAfterBoss = {}, false, false
    for _, r in ipairs(rows) do
        if not r.spell then
            mobsListed[r.mob] = true
            if r.boss then lastBoss = true elseif lastBoss then sawTrashAfterBoss = true end
        end
    end
    t.ok(not mobsListed["Molten Elemental"], "passive-only mob not listed")
    t.ok(mobsListed["Jergosh the Invoker"] and not sawTrashAfterBoss, "bosses after the trash")
    local hw
    for _, r in ipairs(rows) do if r.spell and r.spell.id == 11986 then hw = r end end
    t.ok(hw and hw.mob == "Ragefire Shaman" and hw.auto == "must" and hw.autoSource == "data", "Healing Wave: auto must")

    -- Overrides change the briefing.
    sim.units.nameplate1 = { name = "Ragefire Shaman", friendly = false, level = 13, tier = "elite", power = "MANA" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    sim:Advance(1)
    local function lines()
        local mobs = B.Plan()
        return B.BuildLines(mobs)
    end
    t.eq(lines()[2], "[Bulwark] Best effort: Lightning Bolt", "before: Lightning Bolt best effort")
    B.SetOverride("Ragefire Shaman", 9532, "must")
    t.eq(lines()[1], "[Bulwark] Interrupt: Ragefire Shaman: Healing Wave, Lightning Bolt -> Tankard (Shield Bash)",
        "your must: the interrupter watches both")
    B.SetOverride("Ragefire Shaman", 11986, "ignore", "Healers dispel nothing here")
    local l = lines()
    t.eq(l[1], "[Bulwark] Interrupt: Ragefire Shaman: Lightning Bolt -> Tankard (Shield Bash)", "ignored heal not mentioned")
    t.eq(#l, 1, "an ignored cast's note isn't posted either")
    B.SetOverride("Ragefire Shaman", 11986, nil, "Kick it on sight")
    l = lines()
    t.eq(l[2], "[Bulwark] Note: Healing Wave (Ragefire Shaman): Kick it on sight", "note on an auto cast is posted")
    B.SetOverride("Ragefire Shaman", 11976, "must")   -- Strike (Trogg's spell id) on the Shaman: unknown cast, harmless
    t.ok(B.GetOverride("Ragefire Shaman", 11976).prio == "must", "stored")
    B.SetOverride("Ragefire Shaman", 11976, nil, "  ")
    t.eq(B.GetOverride("Ragefire Shaman", 11976), nil, "empty priority + blank note: removed")
    B.SetOverride("Ragefire Shaman", 9532, nil)
    B.SetOverride("Ragefire Shaman", 11986, nil, nil)
    t.eq(env.BulwarkDB.marking.briefing.overrides["Ragefire Shaman"], nil, "last edit gone: the mob entry goes too")
    B.SetOverride("Ragefire Shaman", 9532, "bogus")
    t.eq(B.GetOverride("Ragefire Shaman", 9532), nil, "invalid priority not stored")

    -- The page: dungeon you're in, rows, picking a priority, typing a note.
    local page = H.page(sim, "briefing")
    t.ok(page and page.rows, "Briefing page built")
    t.contains({ page.zoneDrop.label:GetText() }, "Ragefire Chasm", "opens on the dungeon you're in")
    t.contains({ page.rows[1].mob:GetText() }, "Earthborer", "first row: a mob")
    local hwRow
    for _ = 1, 5 do
        for _, row in ipairs(page.rows) do
            if row:IsShown() and row.spellBtn:IsShown() and row.spell:GetText() == "Healing Wave" then hwRow = row end
        end
        if hwRow then break end
        page.nextPage:Click()
    end
    t.ok(hwRow, "Healing Wave row found")
    t.contains({ hwRow.auto:GetText() }, "must", "auto priority shown")
    hwRow.prio:Click()
    local picked = false
    for _, r in ipairs(env.Bulwark_DropdownList.rows) do
        if r:IsShown() and r.option.key == "info" then r:Click(); picked = true; break end
    end
    t.ok(picked, "info offered in the list")
    t.eq(B.GetOverride("Ragefire Shaman", 11986).prio, "info", "picked priority saved")
    t.contains({ hwRow.prio.label:GetText() }, "info", "row shows your priority")
    hwRow.note:SetText("Purge me")
    hwRow.note:GetScript("OnEnterPressed")(hwRow.note)
    t.eq(B.GetOverride("Ragefire Shaman", 11986).note, "Purge me", "note saved with Enter")
    t.eq(B.GetOverride("Ragefire Shaman", 11986).prio, "info", "priority kept when the note changes")
    hwRow.prio:GetScript("OnClick")(hwRow.prio, "RightButton")
    t.ok(B.GetOverride("Ragefire Shaman", 11986).prio == nil and B.GetOverride("Ragefire Shaman", 11986).note == "Purge me",
        "right-click: back to Auto, note kept")

    -- Every row reads as text (no missing locale keys, e.g. "BRIEF_PRIO_ignore").
    page.prevPage:Click(); page.prevPage:Click(); page.prevPage:Click()
    for _, row in ipairs(page.rows) do
        if row:IsShown() then
            for _, fs in ipairs({ row.auto, row.prio.label, row.mob }) do
                t.eq((fs:GetText() or ""):find("BRIEF_", 1, true), nil, "no raw locale key: " .. tostring(fs:GetText()))
            end
        end
    end
    t.contains({ page.rows[2].auto:GetText() }, "ignore", "Earthborer Acid: default ignore, readable")

    -- The tile switch is on this page now, not on Options.
    t.ok(page.tile:GetChecked(), "tile switch shown, on")
    page.tile:Click()
    t.eq(env.BulwarkDB.marking.briefTile, false, "tile switch turns the option off")
    page.tile:Click()
    t.eq(env.BulwarkDB.marking.briefTile, true, "and on again")
    local options = H.page(sim, "options")
    t.eq(options.boxes.briefTile, nil, "Options page no longer has the tile switch")
    t.ok(options.boxes.learnNames ~= nil, "Options page keeps its planning options")
    page = H.page(sim, "briefing")

    -- Other dungeon from the dropdown.
    page.nextZone:Click()
    t.ok(page.instance ~= RFC, "arrow steps to another dungeon")
    t.eq(#sim.errors, 0, "no Lua errors")
end
