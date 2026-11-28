-- Blizzard's HUD Edit Mode (UI/EditMode.lua): the Audit buff tiles, the debuff row and the Marks HUD get a box there;
-- moves wait for Blizzard's Save, Revert All Changes puts them back, leaving with unsaved moves asks Keep / Discard.
-- Also: the debuff row's own position and size (linked above the buff tiles until moved).
local A = require("audit_helpers")
local M = require("mark_helpers")

-- Models the parts of Blizzard_EditMode that Bulwark uses (EditModeManager.lua, CallbackRegistry.lua).
local function InstallEditMode(s)
    local env = s.env
    local callbacks = {}
    env.EventRegistry = {
        RegisterCallback = function(_, event, fn, owner)
            callbacks[event] = callbacks[event] or {}
            table.insert(callbacks[event], { fn, owner })
        end,
        TriggerEvent = function(_, event, ...)
            for _, c in ipairs(callbacks[event] or {}) do c[1](c[2], ...) end
        end,
    }
    local f = s:CreateFrame("Frame", "EditModeManagerFrame", nil)
    f:Hide()
    f.SaveChangesButton = s:CreateFrame("Button", nil, f)
    f.RevertAllChangesButton = s:CreateFrame("Button", nil, f)
    f.editModeActive = false
    f.reverts = 0
    function f:IsEditModeActive() return self.editModeActive end
    -- As Blizzard's: a flag plus the two buttons (EditModeManager.lua SetHasActiveChanges / HasActiveChanges)
    function f:SetHasActiveChanges(v)
        self.hasActiveChanges = v and true or false
        self.SaveChangesButton:SetEnabled(v)
        self.RevertAllChangesButton:SetEnabled(v)
    end
    function f:HasActiveChanges() return self.hasActiveChanges end
    -- RevertAllChanges -> UpdateLayoutInfo -> ClearActiveChangesFlags, before our post-hook runs
    function f:RevertAllChanges() self.reverts = self.reverts + 1; self:SetHasActiveChanges(false) end
    function f:ClearSelectedSystem() self.cleared = true end
    -- Blizzard's flows: OnShow -> EnterEditMode; Save button -> SaveLayouts; close -> ExitEditMode
    function f:TestEnter()
        self:Show()
        self.editModeActive = true
        self:SetHasActiveChanges(false)
        env.EventRegistry:TriggerEvent("EditMode.Enter")
    end
    function f:TestSave()
        self:SetHasActiveChanges(false)
        env.EventRegistry:TriggerEvent("EditMode.SavedLayouts")
    end
    function f:TestExit()
        self.editModeActive = false
        self:RevertAllChanges()
        self:Hide()
        env.EventRegistry:TriggerEvent("EditMode.Exit")
    end
    f:SetHasActiveChanges(false)
end

return function(_, t)
    local sim = t.fresh(function(s)
        InstallEditMode(s)
        A.Party(s)
        M.install(s)
    end)
    sim:Advance(1)
    local env = sim.env
    local NS = env.Bulwark
    local EM, Bar = NS.EditMode, NS.AuditBar
    local f = env.EditModeManagerFrame
    local anchor, hud = Bar:GetAnchor(), env.Bulwark_MarkHUD
    t.ok(anchor and anchor:IsShown(), "Audit tiles shown")
    t.ok(hud and hud:IsShown(), "Marks HUD shown")

    local boxes = {}
    local function Boxes()
        for _, el in ipairs(EM:GetElements()) do boxes[el.label] = el.overlay end
    end
    local function Drag(box, move)
        box:GetScript("OnDragStart")(box)
        if move then move() end
        box:GetScript("OnDragStop")(box)
    end
    local function MoveAudit(x, y)
        return function()
            anchor:ClearAllPoints()
            anchor:SetPoint("CENTER", env.UIParent, "CENTER", x, y)
        end
    end
    local function MoveHud(x, y)
        return function()
            rawset(hud, "GetLeft", function() return x end)
            rawset(hud, "GetTop", function() return y end)
        end
    end
    local function Previewing()
        for _, tile in ipairs(Bar:GetTiles()) do
            if tile:IsShown() and tile.item and tile.item.label == NS.L["PREVIEW"] then return true end
        end
        return false
    end
    local function AuditPoint()
        return table.concat(env.BulwarkDB.audit.point, " ")
    end

    t.ok(not Previewing(), "locked bar: no preview before Edit Mode")

    -- The sim keeps only a frame's last anchor point: record the bounds' points ourselves.
    local bounds, boundsPoints = Bar:GetBounds(), {}
    local origSetPoint = bounds.SetPoint
    rawset(bounds, "SetPoint", function(self, point, rel, relPoint, x, y)
        boundsPoints[point] = string.format("%s %s", x, y)
        return origSetPoint(self, point, rel, relPoint, x, y)
    end)

    -- Entering Edit Mode: a box over each frame, every Audit tile previewed.
    f:TestEnter()
    Boxes()
    local auditBox, debuffBox, hudBox = boxes["Bulwark Buffs"], boxes["Bulwark Debuffs"], boxes["Bulwark Marks"]
    t.ok(auditBox and auditBox:IsShown(), "buff tiles box shown in Edit Mode")
    t.ok(debuffBox and debuffBox:IsShown(), "debuff row box shown in Edit Mode")
    t.ok(hudBox and hudBox:IsShown(), "HUD box shown in Edit Mode")
    t.ok(Previewing(), "every Audit tile previewed in Edit Mode")
    t.ok(not f.SaveChangesButton:IsEnabled(), "Save greyed out before any move")

    -- The box covers exactly the buff tiles on screen, not the anchor's fixed size.
    local left, right, top = math.huge, -math.huge, -math.huge
    local function Cover(frame)
        local _, _, _, cx, cy = frame:GetPoint()
        left, right, top = math.min(left, cx - 16), math.max(right, cx + 16), math.max(top, cy + 16)
    end
    local n = 0
    for _, tile in ipairs(Bar:GetTiles()) do
        if tile:IsShown() and tile:GetAlpha() > 0 then Cover(tile); n = n + 1 end
    end
    t.ok(n > 10, "many tiles previewed (" .. n .. ")")
    t.eq(string.format("%s / %s", boundsPoints.TOPLEFT, boundsPoints.BOTTOMRIGHT),
        string.format("%s %s / %s %s", left, top, right, -16), "bounds fit the buff tiles")
    t.eq(right - left, n * 32 + (n - 1) * 4, "as wide as the tile row")

    -- The debuff row: its own frame, linked just above the buff tiles until moved.
    local debuffs = Bar:GetDebuffAnchor()
    local dp, drel, _, dx, dy = debuffs:GetPoint()
    t.ok(dp == "CENTER" and drel == anchor and dx == 0 and dy == 48, "debuff row sits above the buff tiles")
    local shownTypes = 0
    for _, dtype in ipairs({ "Magic", "Curse", "Poison", "Disease" }) do
        local holder = Bar:GetDebuffTile(dtype)
        if holder:IsShown() then
            shownTypes = shownTypes + 1
            t.eq(holder:GetParent(), debuffs, dtype .. " tile belongs to the debuff row")
        end
    end
    t.ok(shownTypes > 0, "debuff tiles previewed (" .. shownTypes .. ")")

    -- Edit Mode hides without exiting while some panels are open: our boxes hide with it.
    f:Hide()
    t.ok(not auditBox:IsShown(), "box hides with Edit Mode")
    f:Show()
    t.ok(auditBox:IsShown(), "box back with Edit Mode")

    -- Clicking our box closes Blizzard's selected system.
    auditBox:GetScript("OnMouseDown")(auditBox, "LeftButton")
    t.ok(f.cleared, "Blizzard's selection cleared")

    -- Move the Audit tiles: nothing saved yet, Save + Revert enabled.
    Drag(auditBox, MoveAudit(100, -50))
    t.eq(AuditPoint(), "CENTER CENTER 0 -100", "moved but not saved")
    t.ok(f.SaveChangesButton:IsEnabled() and f.RevertAllChangesButton:IsEnabled(), "Save + Revert enabled")
    f:SetHasActiveChanges(false)   -- Blizzard re-checks its own systems (e.g. reverting one of them)
    t.ok(f.SaveChangesButton:IsEnabled(), "Save stays enabled while Bulwark has unsaved moves")

    -- Blizzard's Save: written.
    f:TestSave()
    t.eq(AuditPoint(), "CENTER CENTER 100 -50", "Save writes the position")
    t.ok(not EM:HasPending(), "nothing pending after Save")
    t.ok(not f.SaveChangesButton:IsEnabled() and not f.RevertAllChangesButton:IsEnabled(),
        "Save + Revert greyed out again after Save (user report 2026-11-28)")

    -- Revert All Changes (Edit Mode still open): the HUD goes back to its saved spot (none: the default corner).
    Drag(hudBox, MoveHud(300, 700))
    t.eq(select(1, hud:GetPoint()), "TOPLEFT", "HUD follows the drag")
    f:RevertAllChanges()
    t.eq(select(1, hud:GetPoint()), "TOPRIGHT", "Revert puts the HUD back")
    t.eq(env.BulwarkDB.marking.hud.point, nil, "HUD position not saved")
    t.ok(not f.SaveChangesButton:IsEnabled(), "Save greyed out after Revert All Changes")

    -- Blizzard's own unsaved change keeps the buttons on when ours are saved
    f:SetHasActiveChanges(true)
    Drag(hudBox, MoveHud(310, 690))
    env.EventRegistry:TriggerEvent("EditMode.SavedLayouts")   -- e.g. a save that left Blizzard's flag set
    t.ok(f.SaveChangesButton:IsEnabled(), "Blizzard still has changes: Save stays enabled")
    f:RevertAllChanges()
    t.ok(not f.SaveChangesButton:IsEnabled(), "both sides clean: greyed out")

    -- Leaving with unsaved moves: Keep / Discard prompt, boxes and preview gone.
    Drag(hudBox, MoveHud(300, 700))
    f:TestExit()
    local prompt = env.Bulwark_EditModePrompt
    t.ok(prompt and prompt:IsShown(), "unsaved moves: prompt on exit")
    t.ok((prompt.text:GetText() or ""):find("Bulwark Marks", 1, true), "prompt names the HUD")
    t.ok(not auditBox:IsShown() and not hudBox:IsShown(), "boxes hidden after Edit Mode")
    t.ok(not Previewing(), "preview ends with Edit Mode")
    prompt.keep:Click()
    local p = env.BulwarkDB.marking.hud.point
    t.ok(p and p.x == 300 and p.y == 700, "Keep saves the HUD position")
    t.ok(not prompt:IsShown(), "prompt closes")

    -- Move the debuff row on its own: saved against the screen, the buff tiles stay put.
    f:TestEnter()
    rawset(debuffs, "GetCenter", function() return 900, 400 end)
    Drag(debuffBox)
    f:TestSave()
    t.eq(table.concat(env.BulwarkDB.audit.debuffPoint, " "), "CENTER BOTTOMLEFT 900 400", "debuff row position saved")
    dp, drel, _, dx, dy = debuffs:GetPoint()
    t.ok(dp == "CENTER" and drel == env.UIParent and dx == 900 and dy == 400, "debuff row on its own spot")
    t.eq(AuditPoint(), "CENTER CENTER 100 -50", "buff tiles unchanged")
    f:TestExit()

    -- Separate sizes
    Bar:SetDebuffScale(1.5)
    t.eq(debuffs:GetScale(), 1.5, "debuff row size")
    t.eq(anchor:GetScale(), 1, "buff tiles keep theirs")
    t.eq(env.BulwarkDB.audit.debuffScale, 1.5, "debuff size saved")

    -- Reset: both back to the defaults, the debuff row linked above the buff tiles again (gap scaled per row)
    Bar:ResetPosition()
    t.eq(env.BulwarkDB.audit.debuffPoint, nil, "debuff position cleared")
    dp, drel, _, dx, dy = debuffs:GetPoint()
    t.ok(dp == "CENTER" and drel == anchor and math.abs(dy - (32 + 16 * 1.5) / 1.5) < 0.01, "linked again")
    Bar:SetDebuffScale(1)

    -- Discard: the Audit tiles go back to their saved position.
    f:TestEnter()
    Drag(auditBox, MoveAudit(-200, 0))
    f:TestSave()
    t.eq(AuditPoint(), "CENTER CENTER -200 0", "saved")
    Drag(auditBox, MoveAudit(100, -50))
    f:TestExit()
    t.ok(prompt:IsShown(), "prompt again")
    prompt.discard:Click()
    t.eq(AuditPoint(), "CENTER CENTER -200 0", "Discard keeps the saved position")
    local point, _, _, x, y = anchor:GetPoint()
    t.eq(string.format("%s %s %s", point, x, y), "CENTER -200 0", "the tiles move back")

    -- Combat: the tiles (secure buttons) refuse to move; the HUD (plain frame) still moves.
    f:TestEnter()
    sim:EnterCombat()
    local before = #sim.output
    Drag(auditBox, MoveAudit(0, 0))
    t.ok(not EM:HasPending(), "no Audit move in combat")
    t.ok(#sim.output > before and sim.output[#sim.output]:find("combat", 1, true), "says why")
    Drag(hudBox, MoveHud(50, 600))
    t.ok(EM:HasPending(), "HUD moves in combat")
    sim:LeaveCombat()
    f:TestSave()
    p = env.BulwarkDB.marking.hud.point
    t.ok(p and p.x == 50 and p.y == 600, "HUD position saved")
    f:TestExit()
    t.ok(not prompt:IsShown(), "saved: no prompt")

    -- An unlocked bar keeps its own green mover outside Edit Mode and hides it inside.
    Bar:SetLocked(false, true)
    t.ok(Previewing(), "unlocked: preview")
    f:TestEnter()
    t.ok(Previewing(), "still previewing in Edit Mode")
    f:TestExit()
    t.ok(Previewing(), "unlocked bar keeps its preview after Edit Mode")
    Bar:SetLocked(true, true)

    -- Saved before the split: the debuff row starts at the buff tiles' size
    local old = t.fresh(function(s)
        InstallEditMode(s)
        A.Party(s)
        s.env.BulwarkDB = { audit = { scale = 1.3, checkUnwanted = true } }
    end)
    t.eq(old.env.BulwarkDB.audit.debuffScale, 1.3, "debuff size starts at the old tile size")
    t.eq(old.env.Bulwark.AuditBar:GetDebuffAnchor():GetScale(), 1.3, "and is applied")

    for _, s in ipairs({ sim, old }) do
        for _, line in ipairs(s.output) do
            t.ok(not line:find("Error in"), "no handler error: " .. line)
        end
    end
end
