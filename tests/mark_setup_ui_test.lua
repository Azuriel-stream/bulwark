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
end
