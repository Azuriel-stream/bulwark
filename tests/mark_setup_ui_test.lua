-- Team page (was TankMarkForever's setup window, tests/setup_ui_test.lua): /bwk mark opens it; the row buttons
-- edit the character's setup.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s) H.install(s) end)
    local NS = sim.env.Bulwark
    sim:Slash("/bwk mark")
    t.ok(NS.Window:IsShown(), "/bwk mark opens the window")
    t.eq((NS.Window:GetActive()), "marking", "on the Marking tab")

    local page = H.page(sim, "team")
    t.eq(#page.rows, 8, "eight rows")
    local rows = sim.env.BulwarkCharDB.marking.setup.rows
    t.eq(page.rows[1].role:GetLabel(), "Tank", "row 1 shows its role")
    page.rows[1].role:Click()
    t.eq(rows[1].role, "CC", "role cycles Tank -> CC")
    t.eq(page.rows[1].role:GetLabel(), "CC", "button repainted (SETUP_CHANGED)")
    page.rows[1].role:Click()
    t.eq(rows[1].role, "TANK", "skull skips Follow, back to Tank")
    page.rows[2].down:Click()
    t.eq(rows[2].icon, 6, "Down moves the row")

    -- Player: picked from a list of the group (was click-to-cycle)
    local Kit = sim.env.Bulwark.Kit
    local function rowsShown()
        local out = {}
        for _, r in ipairs(sim.env.Bulwark_DropdownList.rows) do if r:IsShown() then out[#out + 1] = r end end
        return out
    end
    page.rows[1].player:Click()
    t.ok(Kit.IsListOpen(page.rows[1].player), "player button opens a list")
    local shown = rowsShown()
    local members = sim.env.Bulwark.Marking.Team:Members()
    t.eq(#shown, #members + 1, "one entry per group member, plus none")
    shown[3]:Click()
    t.eq(rows[1].player, members[2].name, "picked member saved")
    t.ok(page.rows[1].player:GetLabel():find(members[2].short, 1, true), "button shows them")
    page.rows[1].player:Click("RightButton")
    t.eq(rows[1].player, nil, "right-click still clears")
    page.rows[1].player:Click()
    rowsShown()[2]:Click()
    page.rows[1].player:Click()
    rowsShown()[1]:Click()
    t.eq(rows[1].player, nil, "the first entry (anyone / nobody) clears too")
end
