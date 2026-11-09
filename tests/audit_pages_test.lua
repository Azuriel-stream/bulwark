-- Audit pages, preview on the Audit tab, commands, area switch and the TankAuditForever guard.
-- (page part ported from TankAuditForever tests/options_test.lua)
local H = require("audit_helpers")

return function(sim, t)
    local NS = sim.env.Bulwark
    local cfg = NS.db.audit
    local Bar = NS.AuditBar
    t.ok(NS:IsAreaRunning("audit"), "Audit runs at login")
    t.ok(Bar:GetAnchor():IsShown(), "tiles anchor shown while Audit runs")

    local function page(key)
        for _, p in ipairs(NS:GetArea("audit").pages) do
            if p.key == key then NS.Window:Open("audit", key); return p end
        end
    end
    local function previewing()
        local shown, total = 0, #Bar:GetTiles()
        for _, tile in ipairs(Bar:GetTiles()) do if tile:IsShown() then shown = shown + 1 end end
        return total > 0 and shown == total
    end

    -- Preview while the window shows the Audit tab; not on other tabs or when closed.
    local checks = page("checks")
    t.ok(previewing(), "all tiles previewed on the Audit tab")
    local poison = Bar:GetDebuffTile("Poison")
    t.ok(poison:IsShown() and poison.bg:IsShown(), "debuff tile squares visible in preview")
    NS.Window:Select("alerts")
    t.ok(not previewing(), "no preview on another tab")
    NS.Window:Select("audit")
    t.ok(previewing(), "preview again back on Audit")
    sim:Slash("/bwk")
    t.ok(not NS.Window:IsShown(), "window closed")
    t.ok(not previewing(), "closing the window ends the preview")
    t.ok(not poison.bg:IsShown(), "debuff squares hidden after preview")

    -- Checks page writes settings; consumables: at most one of + Elixir / + Flask.
    checks = page("checks")
    checks.checks.checkHealthstone:Click()
    t.eq(cfg.checkHealthstone, false, "healthstone checkbox")
    checks.consumables[2]:Click()
    t.eq(cfg.consumableLevel, 2, "+ Elixir selected")
    checks.consumables[3]:Click()
    t.eq(cfg.consumableLevel, 3, "+ Flask selected")
    t.ok(checks.consumables[3]:GetChecked() and not checks.consumables[2]:GetChecked(), "only one add-on checked")
    checks.consumables[3]:Click()
    t.eq(cfg.consumableLevel, 1, "unchecking it means food only")
    -- Consumables when: In a group / Solo are independent (both = always)
    t.ok(checks.consumablesWhen.consumablesInGroup:GetChecked(), "In a group ticked by default")
    t.ok(not checks.consumablesWhen.consumablesSolo:GetChecked(), "Solo unticked by default")
    checks.consumablesWhen.consumablesSolo:Click()
    t.eq(cfg.consumablesSolo, true, "Solo checkbox")
    t.eq(cfg.consumablesInGroup, true, "In a group stays ticked (both)")
    checks.consumablesWhen.consumablesInGroup:Click()
    t.eq(cfg.consumablesInGroup, false, "In a group checkbox")
    checks.consumablesWhen.consumablesInGroup:Click()
    checks.consumablesWhen.consumablesSolo:Click()
    -- Consumables off: its card's options grey out (unclickable, dim label) and keep their values
    local function cardActive(on)
        for _, cb in pairs(checks.consumablesWhen) do if cb:IsEnabled() ~= on then return false end end
        for _, cb in pairs(checks.consumables) do if cb:IsEnabled() ~= on then return false end end
        return true
    end
    t.ok(cardActive(true), "Consumables on: card options active")
    local white = { checks.consumablesWhen.consumablesSolo.Text:GetTextColor() }
    checks.consumables[2]:Click()                    -- + Elixir, to see it survive the greying
    checks.checks.checkConsumables:Click()
    t.eq(cfg.checkConsumables, false, "Consumables unticked")
    t.ok(cardActive(false), "Consumables off: all card options greyed out")
    t.ok(select(1, checks.consumablesWhen.consumablesSolo.Text:GetTextColor()) < white[1], "greyed label is dimmer")
    checks.consumablesWhen.consumablesSolo:Click()
    checks.consumables[3]:Click()
    t.eq(cfg.consumablesSolo, false, "greyed Solo can't be clicked")
    t.eq(cfg.consumableLevel, 2, "greyed + Flask can't be clicked; + Elixir kept")
    t.ok(checks.consumables[2]:GetChecked(), "+ Elixir still shown ticked while greyed")
    NS.Window:Select("alerts")
    checks = page("checks")
    t.ok(cardActive(false), "still greyed after reopening the page")
    checks.checks.checkConsumables:Click()
    t.ok(cardActive(true), "Consumables on again: options active")
    t.eq(select(1, checks.consumablesWhen.consumablesSolo.Text:GetTextColor()), white[1], "label colour restored")
    checks.consumables[2]:Click()
    t.eq(cfg.consumableLevel, 1, "back to food only")
    checks.gratitude:Click()
    t.eq(cfg.gratitude, false, "thanks checkbox")

    -- Blessings: move the 2nd up (warrior list).
    local blessings = page("blessings")
    local before = { cfg.blessingPriority.WARRIOR[1], cfg.blessingPriority.WARRIOR[2] }
    blessings.rows[2].up:Click()
    t.eq(cfg.blessingPriority.WARRIOR[1], before[2], "priority moved up")
    t.eq(cfg.blessingPriority.WARRIOR[2], before[1], "priority swapped")
    t.ok(not blessings.rows[1].up:IsEnabled(), "first row can't move up")

    -- Tiles page: lock, size, reset.
    local tiles = page("tiles")
    tiles.lock:Click()
    t.eq(cfg.locked, false, "unlock from the page")
    tiles.lock:Click()
    t.eq(cfg.locked, true, "lock again")
    tiles.scale.Slider:SetValue(150)
    t.eq(cfg.scale, 1.5, "size saved as a factor")
    cfg.point = { "TOP", "TOP", 10, -10 }
    sim:Slash("/bwk audit reset")
    t.eq(cfg.point[1], "CENTER", "/bwk audit reset restores the position")

    -- Sound page.
    local sound = page("sound")
    sound.sound:Click()
    t.eq(cfg.watchSound, false, "sound checkbox")

    -- Tools page and commands.
    local tools = page("tools")
    t.ok(tools.plan:GetText():find("Tiles:"), "plan summary shown")
    sim:Slash("/bwk audit unlock")
    t.eq(cfg.locked, false, "/bwk audit unlock")
    sim:Slash("/bwk audit lock")
    t.eq(cfg.locked, true, "/bwk audit lock")
    local printed = #sim.output
    sim:Slash("/bwk audit status")
    t.contains({ unpack(sim.output, printed + 1) }, "Tiles:", "/bwk audit status")
    t.eq(#sim.errors, 0, "no errors")

    -- Area off: tiles hidden, no scanning; on again: back.
    sim:Slash("/bwk")
    NS:SetAreaEnabled("audit", false)
    t.ok(not Bar:GetAnchor():IsShown(), "Audit off hides the tiles")
    NS:SetAreaEnabled("audit", true)
    t.ok(Bar:GetAnchor():IsShown(), "Audit on shows them again")

    -- TankAuditForever still loaded: Bulwark's tiles stay hidden (its bar would double up).
    local s2 = t.fresh(function(s)
        H.Party(s)
        s.env.C_AddOns.IsAddOnLoaded = function(name) return name == "Bulwark" or name == "TankAuditForever" end
    end)
    H.Rescan(s2)
    local NS2 = s2.env.Bulwark
    t.eq(NS2:AreaStatus("audit"), "blocked", "Audit waits for TankAuditForever")
    t.ok(not NS2.AuditBar:GetAnchor():IsShown(), "no Bulwark tiles while TankAuditForever is loaded")
    NS2.Window:Open("audit", "checks")
    t.ok(not NS2.AuditBar:GetAnchor():IsShown(), "opening the tab doesn't show them either")
end
