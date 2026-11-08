-- Minimap button: created at login, clicks, hide setting, round/square placement.
return function(sim, t)
    local NS = sim.env.Bulwark
    local Mini = NS.MinimapButton
    local button = Mini:GetButton()
    t.ok(button and button:IsShown(), "button created and shown at login")
    t.eq(button:GetParent(), sim.env.Minimap, "parented to the minimap")

    -- Left-click toggles the window, right-click opens Settings.
    button:Click("LeftButton")
    t.ok(NS.Window:IsShown(), "left-click opens the window")
    button:Click("LeftButton")
    t.ok(not NS.Window:IsShown(), "left-click closes it")
    button:Click("RightButton")
    t.ok(NS.Window:IsShown(), "right-click opens the window")
    t.eq((NS.Window:GetActive()), "settings", "right-click opens Settings")

    -- Round minimap: on a circle around the centre (radius = half width + 10).
    NS.db.minimap.angle = 0
    button:GetScript("OnDragStop")(button)
    sim.env.Minimap:GetScript("OnSizeChanged")
    local function place() for _, fn in ipairs(sim.env.Minimap._hooks.OnSizeChanged or {}) do fn() end end
    place()
    local _, rel, _, x, y = button:GetPoint()
    t.eq(rel, sim.env.Minimap, "anchored to the minimap")
    t.eq(math.floor(x + 0.5), 80, "round: angle 0 sits east at radius 80")
    t.eq(math.floor(y + 0.5), 0, "round: angle 0 on the horizontal axis")

    -- Square minimap (GetMinimapShape from another addon): on the square's edge, corners included.
    sim.env.GetMinimapShape = function() return "SQUARE" end
    NS.db.minimap.angle = 45
    place()
    _, _, _, x, y = button:GetPoint()
    t.eq(math.floor(x + 0.5), 74, "square: 45 degrees goes to the corner (x)")
    t.eq(math.floor(y + 0.5), 74, "square: 45 degrees goes to the corner (y)")
    sim.env.GetMinimapShape = nil

    -- Dragging stores the angle from the cursor.
    sim.cursor = { 0, 100 }   -- straight above the minimap centre (sim centre = 0,0 when unknown)
    local center = function() return 0, 0 end
    sim.env.Minimap.GetCenter = center
    sim.env.Minimap.GetEffectiveScale = function() return 1 end
    button:GetScript("OnDragStart")(button)
    button:GetScript("OnUpdate")(button)
    button:GetScript("OnDragStop")(button)
    t.eq(math.floor(NS.db.minimap.angle + 0.5), 90, "drag north saves 90 degrees")
    t.eq(button:GetScript("OnUpdate"), nil, "drag stop ends the update loop")

    -- Settings checkbox and /bwk minimap hide and show it; the choice is saved.
    NS.Window:Select("settings", "window")
    local page
    for _, p in ipairs(NS:GetArea("settings").pages) do if p.key == "window" then page = p end end
    t.ok(page.minimap:GetChecked(), "checkbox shows the button is on")
    page.minimap:Click()
    t.ok(not button:IsShown(), "checkbox hides the button")
    t.eq(NS.db.minimap.hide, true, "hidden is saved")
    sim:Slash("/bwk minimap")
    t.ok(button:IsShown(), "/bwk minimap shows it again")
    t.eq(NS.db.minimap.hide, false, "shown is saved")

    -- Hidden at login: not created until asked for.
    local s2 = t.fresh(function(s) s.env.BulwarkDB = { minimap = { hide = true } } end)
    t.eq(s2.env.Bulwark.MinimapButton:GetButton(), nil, "hidden button isn't created at login")
    s2:Slash("/bwk minimap")
    local b2 = s2.env.Bulwark.MinimapButton:GetButton()
    t.ok(b2 and b2:IsShown(), "created on demand")

    -- Blizzard's addon compartment callback toggles the window too.
    sim.env.Bulwark_OnCompartmentClick("Bulwark", "LeftButton")
    t.eq(#sim.errors, 0, "compartment callback runs")
end
