-- Main window: open/close, tabs, side menu, lazy pages, remembered tab, scale and position.
return function(sim, t)
    local NS = sim.env.Bulwark
    t.ok(NS and NS.db and NS.char, "SavedVariables initialized")
    local Window = NS.Window

    -- /bwk toggles; Esc closes (UISpecialFrames).
    t.ok(not Window:IsShown(), "window not created or shown at login")
    t.eq(sim.env.BulwarkWindow, nil, "window is built lazily, not at load")
    sim:Slash("/bwk")
    t.ok(Window:IsShown(), "/bwk opens the window")
    local found = false
    for _, name in ipairs(sim.env.UISpecialFrames) do if name == "BulwarkWindow" then found = true end end
    t.ok(found, "Esc closes the window (UISpecialFrames)")
    t.eq((Window:GetActive()), "alerts", "first open shows the first area")
    sim:Slash("/bulwark")
    t.ok(not Window:IsShown(), "/bulwark closes it again")

    -- Tabs in order, Settings last; every tab and page builds without errors.
    local keys = {}
    for _, area in ipairs(NS.areas) do keys[#keys + 1] = area.key end
    t.eq(table.concat(keys, ","), "alerts,audit,marking,utilities,settings", "area order")
    sim:Slash("/bwk")
    for _, area in ipairs(NS.areas) do
        Window.tabs[area.key]:Click()
        t.eq((Window:GetActive()), area.key, "tab click selects " .. area.key)
        t.ok(Window.navs[area.key]:IsShown(), "side menu of " .. area.key .. " shown")
        for _, entry in ipairs(Window.navs[area.key].entries) do
            entry:Click()
            local _, page = Window:GetActive()
            t.eq(page, entry.page.key, "entry selects page " .. entry.page.key)
            t.ok(entry.page.frame and entry.page.frame:IsShown(), "page " .. entry.page.key .. " built and shown")
        end
    end
    t.eq(#sim.errors, 0, "no Lua errors building pages")

    -- Only the active page is shown.
    Window:Select("audit", "tiles")
    local shown = 0
    for _, area in ipairs(NS.areas) do
        for _, page in ipairs(area.pages) do
            if page.frame and page.frame:IsShown() then shown = shown + 1 end
        end
    end
    t.eq(shown, 1, "exactly one page visible")

    -- The tab and page are remembered per character, also per area.
    t.eq(NS.char.lastTab, "audit", "last tab saved per character")
    t.eq(NS.char.lastPage.audit, "tiles", "last page saved per area")
    Window:Select("alerts")
    Window:Select("audit")
    local _, page = Window:GetActive()
    t.eq(page, "tiles", "returning to an area shows its last page")
    sim:Slash("/bwk"); sim:Slash("/bwk")
    t.eq((Window:GetActive()), "audit", "reopening shows the last tab")

    -- /bwk <area> opens that tab; "mark" is short for marking.
    sim:Slash("/bwk mark")
    t.eq((Window:GetActive()), "marking", "/bwk mark opens Marking")
    sim:Slash("/bwk settings")
    t.eq((Window:GetActive()), "settings", "/bwk settings opens Settings")

    -- Scale is clamped; reset restores 100 % and centre.
    Window:SetScale(3)
    t.eq(NS.db.ui.scale, 1.4, "scale clamped to 140 %")
    t.eq(Window:GetFrame():GetScale(), 1.4, "frame scale applied")
    Window:SetScale(0.1)
    t.eq(NS.db.ui.scale, 0.6, "scale clamped to 60 %")
    NS.db.ui.x, NS.db.ui.y = 100, 700
    Window:SetScale(1.2)
    t.eq(NS.db.ui.x, 50, "top-left kept on screen when the scale changes (x)")
    t.eq(NS.db.ui.y, 350, "top-left kept on screen when the scale changes (y)")
    sim:Slash("/bwk reset")
    t.eq(NS.db.ui.scale, 1, "/bwk reset: scale 100 %")
    t.eq(NS.db.ui.x, nil, "/bwk reset: position cleared")

    -- Size slider: dragging only moves the label; the window resizes once on release ([in-game] applying every
    -- step rescaled the slider under the cursor and ran it to 140 %). Stepper clicks apply at once.
    Window:Select("settings", "window")
    local winPage
    for _, p in ipairs(NS:GetArea("settings").pages) do if p.key == "window" then winPage = p end end
    local inner = winPage.scale.Slider
    local function mouse(script) for _, fn in ipairs(inner._hooks[script] or {}) do fn(inner) end end
    mouse("OnMouseDown")
    inner:SetValue(120)
    inner:SetValue(130)
    t.eq(NS.db.ui.scale, 1, "no resize while dragging")
    mouse("OnMouseUp")
    t.eq(NS.db.ui.scale, 1.3, "resize once on release")
    inner:SetValue(110)
    t.eq(NS.db.ui.scale, 1.1, "stepper/programmatic changes apply at once")
    mouse("OnMouseDown"); mouse("OnMouseUp")
    t.eq(NS.db.ui.scale, 1.1, "a click without a move changes nothing")
    sim:Slash("/bwk reset")

    -- Works in combat: open, switch tabs, close.
    sim:Slash("/bwk"); sim:Slash("/bwk")
    t.ok(Window:IsShown(), "window shown")
    sim:EnterCombat()
    Window.tabs.alerts:Click()
    Window.tabs.settings:Click()
    sim:Slash("/bwk")
    t.ok(not Window:IsShown(), "closes in combat")
    sim:Slash("/bwk")
    t.ok(Window:IsShown(), "opens in combat")
    sim:LeaveCombat()
    t.eq(#sim.violations, 0, "no blocked actions")

    -- No Blizzard dropdown menus (kb/gotchas.md#menu-crash).
    for _, f in ipairs(sim.frames) do
        t.ok(f._type ~= "DropdownButton", "no Blizzard menu dropdowns")
    end
end
