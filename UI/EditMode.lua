local ADDON_NAME, NS = ...

-- Blizzard's HUD Edit Mode: Bulwark's on-screen frames (Audit tiles, Marks HUD) show up there as blue boxes you can
-- drag, and follow Blizzard's Save / Revert All Changes.
-- Addon frames can't join Edit Mode's own system list (it's secure: writing to it taints Edit Mode), so we follow it
-- from outside, touching Blizzard's frame only through widget calls, HookScript and hooksecurefunc (no field writes):
--   EventRegistry "EditMode.Enter" / "EditMode.Exit"   our session starts / ends
--   EventRegistry "EditMode.SavedLayouts"              Blizzard's Save: our moves are written to the saved variables
--   hooksecurefunc RevertAllChanges (while active)     Revert All Changes: our moves go back
--   leaving with unsaved moves                         our own Keep / Discard prompt (Blizzard's warning can't see them)
-- Blizzard's Save button stays greyed out while only addon frames changed, so we enable it ourselves (and again
-- whenever Blizzard re-disables it, via a SetHasActiveChanges hook).
local EM = NS:RegisterModule("EditMode")
local Kit, L = NS.Kit, NS.L

local elements = {}   -- registration order
local pending = {}    -- [element] = position moved this session, not saved yet
local active = false
local hooked = false
local prompt

-- Blizzard's selection box (Blizzard_EditMode EditModeSystemTemplates.lua EditModeSystemSelectionLayout)
local LAYOUT = {
    TopRightCorner    = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    TopLeftCorner     = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    BottomLeftCorner  = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    TopEdge           = { atlas = "_%s-NineSlice-EdgeTop" },
    BottomEdge        = { atlas = "_%s-NineSlice-EdgeBottom" },
    LeftEdge          = { atlas = "!%s-NineSlice-EdgeLeft" },
    RightEdge         = { atlas = "!%s-NineSlice-EdgeRight" },
    Center            = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local KIT_IDLE, KIT_MOVING = "editmode-actionbar-highlight", "editmode-actionbar-selected"

-- Blue box like Blizzard's; a plain tinted texture if the nine-slice can't be built.
local function Paint(box, textureKit)
    if box.fallback then return end
    local ok = NineSliceUtil and NineSliceUtil.ApplyLayout and pcall(NineSliceUtil.ApplyLayout, box, LAYOUT, textureKit)
    if not ok then
        box.fallback = Kit.Fill(box, { 0.25, 0.6, 1, 0.3 }, "BACKGROUND")
    end
end

local function Blizzard()
    return EditModeManagerFrame
end

local function IsFunction(t, key)
    return type(t) == "table" and type(t[key]) == "function"
end

-- Enable Save + Revert All Changes while we have unsaved moves (widget state only, no Lua fields).
local function ShowUnsaved()
    local f = Blizzard()
    if not (f and next(pending)) then return end
    if f.SaveChangesButton then pcall(f.SaveChangesButton.SetEnabled, f.SaveChangesButton, true) end
    if f.RevertAllChangesButton then pcall(f.RevertAllChangesButton.SetEnabled, f.RevertAllChangesButton, true) end
end

local function Commit()
    for el, pos in pairs(pending) do el.Save(pos) end
    wipe(pending)
end

local function Revert()
    for el in pairs(pending) do el.Restore() end
    wipe(pending)
end

local function PendingLabels()
    local names = {}
    for _, el in ipairs(elements) do
        if pending[el] then names[#names + 1] = el.label end
    end
    return table.concat(names, ", ")
end

local function OverlayShown()
    local f = Blizzard()
    return active and f and f:IsShown()
end

local function UpdateOverlays()
    local show = OverlayShown()
    for _, el in ipairs(elements) do
        if el.overlay then el.overlay:SetShown(show and el.IsAvailable() and true or false) end
    end
end

local function CreateOverlay(el, frame)
    local o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints(el.GetBounds and el.GetBounds() or frame)
    o:SetFrameLevel(frame:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    Paint(o, KIT_IDLE)
    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.label:SetPoint("CENTER")
    o.label:SetText(el.label)
    o.label:Hide()

    o:SetScript("OnEnter", function(self)
        self.label:Show()
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(el.label, 1, 1, 1)
        GameTooltip:AddLine(L["EDITMODE_HINT"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    o:SetScript("OnLeave", function(self)
        if not self.moving then self.label:Hide() end
        GameTooltip:Hide()
    end)
    o:SetScript("OnMouseDown", function()
        -- Close Blizzard's settings panel for whatever system was selected. Out of combat only: there it runs
        -- through Blizzard's secure delegate (EditModeManagerFrameMixin:ClearSelectedSystem).
        local f = Blizzard()
        if IsFunction(f, "ClearSelectedSystem") and not InCombatLockdown() then pcall(f.ClearSelectedSystem, f) end
    end)
    o:SetScript("OnDragStart", function(self)
        if el.CanMove and not el.CanMove() then
            NS:Print(L["EDITMODE_COMBAT"], el.label)
            return
        end
        self.moving = true
        Paint(self, KIT_MOVING)
        GameTooltip:Hide()
        frame:StartMoving()
    end)
    o:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false
        frame:StopMovingOrSizing()
        Paint(self, KIT_IDLE)
        self.label:Hide()
        pending[el] = el.Read()
        ShowUnsaved()
    end)
    o:Hide()
    el.overlay = o
end

-- Bulwark's own Keep / Discard prompt (not a StaticPopup: addon popups taint Blizzard's shared popup frames).
local function Prompt()
    if prompt then return prompt end
    local p = CreateFrame("Frame", "Bulwark_EditModePrompt", UIParent)
    p:SetSize(360, 112)
    p:SetPoint("TOP", UIParent, "TOP", 0, -160)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    Kit.Fill(p, Kit.C.bg)
    Kit.Border(p, Kit.C.gold)
    p.text = Kit.Paragraph(p, "", 330, 12)
    p.text:SetPoint("TOP", 0, -14)
    p.text:SetJustifyH("CENTER")
    p.keep = Kit.Button(p, L["EDITMODE_KEEP"], 120, function()
        Commit()
        p:Hide()
    end)
    p.keep:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -6, 12)
    p.discard = Kit.Button(p, L["EDITMODE_DISCARD"], 120, function()
        Revert()
        p:Hide()
    end)
    p.discard:SetPoint("BOTTOMLEFT", p, "BOTTOM", 6, 12)
    p:Hide()
    prompt = p
    return p
end

local function OnEnter()
    active = true
    if prompt then prompt:Hide() end   -- back in Edit Mode before answering: the moves stay pending
    for _, el in ipairs(elements) do
        local frame = el.GetFrame()
        if frame and not el.overlay then CreateOverlay(el, frame) end
        if el.OnEnter then el.OnEnter() end
    end
    UpdateOverlays()
    ShowUnsaved()
end

local function OnExit()
    active = false
    UpdateOverlays()
    for _, el in ipairs(elements) do
        if el.OnExit then el.OnExit() end
    end
    if next(pending) then
        local p = Prompt()
        p.text:SetText(string.format(L["EDITMODE_UNSAVED"], PendingLabels()))
        p:Show()
    end
end

-- element = {
--   label,                  shown on the box and in the prompt
--   GetFrame(),             the frame to move (nil until it exists)
--   GetBounds(),            optional: the area the box covers, if not the whole frame (e.g. the tiles on screen)
--   IsAvailable(),          show the box now? (frame shown, its area on)
--   CanMove(),              optional: false = refuse the drag (e.g. secure children in combat)
--   Read() -> pos,          position after a drag (the frame has already moved)
--   Save(pos),              write pos to the saved variables
--   Restore(),              put the frame back at its saved position
--   OnEnter(), OnExit(),    optional: e.g. show every Audit tile while Edit Mode is open
-- }
function EM:Register(element)
    elements[#elements + 1] = element
    if active then OnEnter() end
end

function EM:IsActive() return active end
function EM:HasPending() return next(pending) ~= nil end
function EM:GetElements() return elements end   -- tests

local function Hook()
    local f = Blizzard()
    if hooked or not (IsFunction(EventRegistry, "RegisterCallback") and IsFunction(f, "IsEditModeActive")) then return end
    hooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", OnEnter, EM)
    EventRegistry:RegisterCallback("EditMode.Exit", OnExit, EM)
    EventRegistry:RegisterCallback("EditMode.SavedLayouts", Commit, EM)
    if IsFunction(f, "RevertAllChanges") then
        hooksecurefunc(f, "RevertAllChanges", function(self)
            -- Exiting calls it too, after clearing the active flag: then the Keep / Discard prompt decides.
            if self:IsEditModeActive() then Revert() end
        end)
    end
    if IsFunction(f, "SetHasActiveChanges") then
        hooksecurefunc(f, "SetHasActiveChanges", ShowUnsaved)
    end
    -- Edit Mode hides without exiting while some panels are open: hide our boxes with it.
    f:HookScript("OnShow", UpdateOverlays)
    f:HookScript("OnHide", UpdateOverlays)
    if f:IsEditModeActive() then OnEnter() end
end

function EM:OnEnable()
    Hook()
end
