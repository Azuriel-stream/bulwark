local ADDON_NAME, NS = ...
local MK = NS.Marking
local L = MK.L

-- Moving over from TankMarkForever: its secure buttons were TMF_*, Bulwark's are BWK_*. Key bindings are stored by
-- name ("CLICK TMF_PackButton:LeftButton"), so when Marking starts (TankMarkForever not loaded), keys still bound to
-- the old names are moved to the new ones and saved. Macros that /click the old names are only listed: rewriting
-- the player's macros unasked would be too much (kb/addons/Bulwark.md).
local Keys = MK:RegisterModule("Keys")

local BUTTONS = { "PackButton", "SkullButton", "CycleButton", "ClearButton" }
local frame = CreateFrame("Frame", "Bulwark_MarkKeysFrame")

local function Binding(prefix, button)
    return "CLICK " .. prefix .. button .. ":LeftButton"
end

-- Keys bound to TankMarkForever's buttons go to Bulwark's. Out of combat only. Returns the moved keys.
function Keys.MoveOldBindings()
    if InCombatLockdown() then return nil end
    local moved = {}
    for _, button in ipairs(BUTTONS) do
        for _, key in ipairs({ GetBindingKey(Binding("TMF_", button)) }) do
            local ok, result = pcall(SetBinding, key, Binding("BWK_", button))
            if ok and result ~= false then table.insert(moved, key) end
        end
    end
    if #moved > 0 then
        SaveBindings(GetCurrentBindingSet())
        MK.db.keysMoved = true
    end
    return moved
end

-- Names of the player's macros (account and character) that still /click a TMF_ button.
function Keys.OldMacros()
    local found = {}
    local numAccount, numCharacter = GetNumMacros()
    local consts = Constants and Constants.MacroConsts
    local base = tonumber(consts and consts.MAX_ACCOUNT_MACROS) or 120
    local function Check(index)
        local name, _, body = GetMacroInfo(index)
        if type(body) == "string" and body:find("TMF_", 1, true) then table.insert(found, name or "?") end
    end
    for i = 1, numAccount or 0 do Check(i) end
    for i = base + 1, base + (numCharacter or 0) do Check(i) end
    return found
end

-- Current keys for the four marking buttons (nil = unbound).
function Keys.Current()
    local keys = {}
    for _, button in ipairs(BUTTONS) do keys[button] = GetBindingKey(Binding("BWK_", button)) end
    return keys
end

local function Check()
    local moved = Keys.MoveOldBindings()
    if moved and #moved > 0 then
        MK:Print(L["KEYS_MOVED"], table.concat(moved, ", "))
    end
    local macros = Keys.OldMacros()
    if #macros > 0 then
        MK:Print(L["KEYS_OLD_MACROS"], table.concat(macros, ", "))
    end
end

frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Check()
end)

function Keys:OnEnable()
    if InCombatLockdown() then
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- reloaded in combat: check once combat ends
    else
        Check()
    end
end

function Keys:OnDisable()
    frame:UnregisterAllEvents()
end
