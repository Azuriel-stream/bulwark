local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Forever: addon code can't call SetRaidTarget (ADDON_ACTION_FORBIDDEN everywhere, kb/gotchas.md#setraidtarget).
-- Marks are applied by Blizzard's secure `raidtarget` action on a key press. The plan is written into secure
-- button attributes out of combat; in combat the attributes are frozen, and only secure snippets may change them.
local Marker = MK:RegisterModule("Marker")

local MAX_MARKS = 8
local markButtons = {}

local function SecureButton(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    return b
end

-- One raidtarget button per planned mob. /click sends down=false, so these act on the up click.
for k = 1, MAX_MARKS do
    local b = SecureButton("BWK_Mark" .. k)
    b:SetAttribute("type", "raidtarget")
    b:SetAttribute("action", "none")   -- "none" is a no-op; an unset unit would fall back to the target
    b:SetAttribute("useOnKeyDown", false)
    markButtons[k] = b
end

-- Mark planned pack: a macro that clicks the planned mark buttons. One key press marks the whole pack
-- (4 at once confirmed in-game; set-unmarked keeps marks mobs already wear).
local packButton = SecureButton("BWK_PackButton")
packButton:SetAttribute("type", "macro")
packButton:SetAttribute("macrotext", "")
packButton:SetAttribute("useOnKeyDown", true)


-- In combat the pack is already marked and the group follows the icon order (skull, then cross, ...). The in-combat
-- keys are overrides on your TARGET: a nameplateN token is no reliable mob identity in combat (kb/gotchas.md#token-churn)
-- and mouseover is too unreliable in a fast fight. The snippet skips friendly or dead targets.
local header = CreateFrame("Frame", "BWK_SecureHeader", UIParent, "SecureHandlerBaseTemplate")
local HOSTILE_TARGET = [[
    if not SecureCmdOptionParse("[@target,harm,nodead] 1") then return false end
    self:SetAttribute("unit", "target")
]]

-- Next skull: move skull onto your target (an override; the group focuses skull).
local skullButton = SecureButton("BWK_SkullButton")
skullButton:SetAttribute("type", "raidtarget")
skullButton:SetAttribute("action", "set")
skullButton:SetAttribute("marker", 8)
skullButton:SetAttribute("useOnKeyDown", true)
SecureHandlerWrapScript(skullButton, "OnClick", header, [[
    if not down then return end
]] .. HOSTILE_TARGET)

-- Next free icon: mark your target with the next icon nobody wears (adds). Skips mobs that already wear one.
local cycleButton = SecureButton("BWK_CycleButton")
cycleButton:SetAttribute("type", "raidtarget")
cycleButton:SetAttribute("action", "set-unmarked")
cycleButton:SetAttribute("useOnKeyDown", true)
cycleButton:SetAttribute("cycn", 0)
SecureHandlerWrapScript(cycleButton, "OnClick", header, [[
    if not down then return end
    local n = self:GetAttribute("cycn") or 0
    if n == 0 then return false end
]] .. HOSTILE_TARGET .. [[
    local i = (self:GetAttribute("cyci") or 0) % n + 1
    self:SetAttribute("cyci", i)
    self:SetAttribute("marker", self:GetAttribute("cyc" .. i))
]])

-- Follow marks: one raidtarget button per Follow row, on the group member who wears it (the tank).
-- set-unmarked, never set or toggle: re-applying the icon a unit already wears removes it (kb/gotchas.md#mark-toggle).
local followButtons = {}
for k = 1, MAX_MARKS do
    local b = SecureButton("BWK_Follow" .. k)
    b:SetAttribute("type", "raidtarget")
    b:SetAttribute("action", "none")
    b:SetAttribute("useOnKeyDown", false)
    followButtons[k] = b
end

-- Clear all marks (and the pack selection), then put the follow marks back: clear-all can't spare one icon, and
-- addon code can't tell which mob wears which icon to clear them one by one.
local clearAllButton = SecureButton("BWK_ClearAll")
clearAllButton:SetAttribute("type", "raidtarget")
clearAllButton:SetAttribute("action", "clear-all")
clearAllButton:SetAttribute("useOnKeyDown", false)

local CLEAR_MACRO = "/click BWK_ClearAll"
local clearButton = SecureButton("BWK_ClearButton")
clearButton:SetAttribute("type", "macro")
clearButton:SetAttribute("macrotext", CLEAR_MACRO)
clearButton:SetAttribute("useOnKeyDown", true)
clearButton:HookScript("PreClick", function(_, _, down)
    if down and not InCombatLockdown() then MK.Plates:ClearSelection(true) end
end)

Marker.buttons = { pack = packButton, skull = skullButton, cycle = cycleButton, clear = clearButton,
                   marks = markButtons, follows = followButtons, clearAll = clearAllButton }

-- Debug trace of key presses (insecure reads of the same units).
local function UnitState(unit)
    if not unit then return "nil" end
    local okD, dead = pcall(UnitIsDead, unit)
    return string.format("%s(%s%s%s)", unit, UnitExists(unit) and "exists" or "gone",
        okD and dead == true and ",dead" or "", MK.Plates:IsMarked(unit) and ",marked" or "")
end

packButton:HookScript("PreClick", function(self, _, down)
    if not down then return end
    MK:Debug("pack key: macro=[%s]", (string.gsub(self:GetAttribute("macrotext") or "", "\n", " ")))
end)
clearButton:HookScript("PreClick", function(self, _, down)
    if not down then return end
    MK:Debug("clear key: macro=[%s]", (string.gsub(self:GetAttribute("macrotext") or "", "\n", " ")))
end)
skullButton:HookScript("PostClick", function(self, _, down)
    if not down then return end
    MK:Debug("skull key: unit=%s", UnitState(self:GetAttribute("unit")))
end)
cycleButton:HookScript("PostClick", function(self, _, down)
    if not down then return end
    MK:Debug("cycle key: marker=%s (%s of %s) unit=%s", tostring(self:GetAttribute("marker")),
        tostring(self:GetAttribute("cyci")), tostring(self:GetAttribute("cycn")), UnitState(self:GetAttribute("unit")))
end)


-- Write a plan into the secure attributes. Out of combat only (SetAttribute on secure frames is blocked in combat).
function Marker:Apply(plan)
    if InCombatLockdown() then return false end
    -- Follow marks first: the pack key also restores a follow mark someone removed, and the clear key puts them back.
    local follows, followLines = MK.isEnabled and MK.Team:GetFollows() or {}, {}
    for k, b in ipairs(followButtons) do
        local f = follows[k]
        if f then
            b:SetAttribute("unit", f.unit)
            b:SetAttribute("marker", f.icon)
            b:SetAttribute("action", "set-unmarked")
            table.insert(followLines, "/click BWK_Follow" .. k)
        else
            b:SetAttribute("action", "none")
        end
    end
    clearButton:SetAttribute("macrotext", table.concat({ CLEAR_MACRO, unpack(followLines) }, "\n"))

    local lines = { unpack(followLines) }
    for k, b in ipairs(markButtons) do
        local e = plan.entries[k]
        if e and MK.isEnabled then
            b:SetAttribute("unit", e.rec.token)
            b:SetAttribute("marker", e.icon)
            b:SetAttribute("action", "set-unmarked")
            table.insert(lines, "/click BWK_Mark" .. k)
        else
            b:SetAttribute("action", "none")
        end
    end
    packButton:SetAttribute("macrotext", table.concat(lines, "\n"))

    -- Cycle icons: ladder icons that neither the plan nor any mob uses. Reusing a worn icon would move it.
    local taken, cyc = {}, {}
    for icon in pairs(plan.reserved or {}) do taken[icon] = true end
    for _, e in ipairs(plan.entries) do taken[e.icon] = true end
    for _, icon in ipairs(MK.Team:KillIcons()) do
        if not taken[icon] then table.insert(cyc, icon) end
    end
    for i = 1, MAX_MARKS do
        cycleButton:SetAttribute("cyc" .. i, cyc[i])
    end
    cycleButton:SetAttribute("cycn", MK.isEnabled and math.min(#cyc, MAX_MARKS) or 0)
    cycleButton:SetAttribute("cyci", 0)
    return true
end

function Marker:GetKeys()
    local function key(button)
        return GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
    end
    return key(packButton), key(skullButton), key(cycleButton), key(clearButton)
end

local frame = CreateFrame("Frame", "BWK_MarkerFrame")
frame:SetScript("OnEvent", function(_, event)
    if event == "RAID_TARGET_UPDATE" and not InCombatLockdown() then
        -- Marked mobs leave the plan (their plates now show an icon).
        MK.Plates.Changed()
    end
end)

function Marker:OnInitialize()
    MK:On("PLAN_CHANGED", function(plan) Marker:Apply(plan) end)
end

function Marker:OnEnable()
    frame:RegisterEvent("RAID_TARGET_UPDATE")
end

function Marker:OnDisable()
    frame:UnregisterAllEvents()
    Marker:Apply({ entries = {}, killOrder = {}, overflow = {} })
end
