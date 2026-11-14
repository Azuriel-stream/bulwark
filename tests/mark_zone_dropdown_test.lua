-- Mobs page: any zone from the dropdown (Kit.Dropdown, our own list), the arrows still step, the list scrolls,
-- and closing the window / changing page closes the list.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s) H.install(s) end)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local Kit = env.Bulwark.Kit
    local here = MK.Plates.zone

    -- 20 zones with saved mobs (more than the list shows at once), plus the zone you're in
    for i = 1, 20 do
        MK.db.mobs[string.format("Zone %02d", i)] = { names = { ["Mob " .. i] = { type = "TANK", prio = 5 } }, sigs = {} }
    end
    local page = H.page(sim, "mobs")
    t.ok(page.zoneDrop:GetLabel():find(here, 1, true), "starts on the zone you're in: " .. tostring(page.zoneDrop:GetLabel()))

    -- Open: one row per zone, the current one marked, scrolled so it's visible
    page.zoneDrop:Click()
    t.ok(Kit.IsListOpen(page.zoneDrop), "click opens the list")
    local list = env.Bulwark_DropdownList
    local shown = 0
    for _, r in ipairs(list.rows) do if r:IsShown() then shown = shown + 1 end end
    t.eq(shown, 14, "14 rows visible, the rest scroll")
    t.ok(list.track:IsShown(), "scroll bar shown for a long list")

    -- Scroll to the top and pick a zone far from the current one
    for _ = 1, 10 do list:GetScript("OnMouseWheel")(list, 1) end
    local pick
    for _, r in ipairs(list.rows) do
        if r:IsShown() and r.option.key == "Zone 03" then pick = r end
    end
    t.ok(pick, "Zone 03 reachable at the top of the list")
    t.ok(pick.text:GetText():find("(1)", 1, true), "entry count in the label")
    pick:Click()
    t.ok(not Kit.IsListOpen(), "picking closes the list")
    t.eq(page.zone, "Zone 03", "page switched to the picked zone")
    t.ok(page.zoneDrop:GetLabel():find("Zone 03", 1, true), "dropdown shows it")
    t.ok(page.rows[1]:IsShown() and page.rows[1].label:GetText() == "Mob 3", "its mobs listed")

    -- Arrows still step to the neighbours
    page.nextZone:Click()
    t.eq(page.zone, "Zone 04", "> steps to the next zone")

    -- A click outside closes it; so do a page change and closing the window
    page.zoneDrop:Click()
    env.Bulwark_DropdownCatcher:Click()
    t.ok(not Kit.IsListOpen(), "click outside closes the list")
    page.zoneDrop:Click()
    page.zoneDrop:Click()
    t.ok(not Kit.IsListOpen(), "second click on the button closes it")
    page.zoneDrop:Click()
    H.page(sim, "team")
    t.ok(not Kit.IsListOpen(), "changing page closes the list")
    H.page(sim, "mobs")
    page.zoneDrop:Click()
    env.Bulwark.Window:GetFrame():Hide() -- X / Esc
    t.ok(not Kit.IsListOpen(), "closing the window closes the list")
end
