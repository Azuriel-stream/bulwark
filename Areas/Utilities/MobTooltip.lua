local ADDON_NAME, NS = ...
local L, Utils, Avoidance = NS.L, NS.Utils, NS.Avoidance

-- Mob tooltip note (option, off by default; user 2026-11-12: tooltip line, not a target-frame mark): hovering a
-- hostile mob that can land crushing blows on you adds "Can crush you: 15.00% crushing blows, 4.84% crits".
-- Nothing for mobs that can't crush ("no line = fine"). Uses the last character-sheet snapshot, without block
-- cooldowns (what a pull does to you before Shield Block is up). Warrior and Paladin.
local MobTooltip = NS:RegisterModule("MobTooltip", "utilities")
local hooked = false

local CLASSES = { WARRIOR = true, PALADIN = true }

local function cfg() return NS.db.utilities end

local function Plain(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or Utils.IsSecret(v) then return nil end
    return v
end

-- Levels above the player for a mob level; skull (-1) = a raid boss at 60 (+3), otherwise at least 10 above.
function MobTooltip.Offset(mobLevel, playerLevel)
    if mobLevel == -1 then return playerLevel >= 60 and 3 or 10 end
    return mobLevel - playerLevel
end

-- Text for a mob of the given level, or nil when it can't crush the player.
function MobTooltip.Line(snap, mobLevel)
    if not (snap and type(mobLevel) == "number") then return nil end
    local offset = MobTooltip.Offset(mobLevel, snap.level)
    if offset < 1 then return nil end
    local r = Avoidance.Compute(snap, { offset = offset })
    if not r.canCrush or r.table.crush <= 0 then return nil end
    return string.format(L["TT_MOB_CRUSH"], string.format("%.2f%%", r.table.crush), string.format("%.2f%%", r.table.crit))
end

function MobTooltip.OnTooltip(tooltip)
    if not (NS:IsAreaRunning("utilities") and cfg().mobTooltip and CLASSES[NS.playerClass]) then return end
    local okUnit, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not okUnit or type(unit) ~= "string" or Utils.IsSecret(unit) then return end
    if Plain(UnitIsPlayer, unit) ~= false or Plain(UnitCanAttack, "player", unit) ~= true then return end
    local line = MobTooltip.Line(Avoidance:Get(), Plain(UnitLevel, unit))
    if line then tooltip:AddLine(line, 1.00, 0.45, 0.30) end
end

-- Installed once (a post-call can't be removed); checks the option each time.
function MobTooltip:OnEnable()
    if hooked then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
    hooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip == GameTooltip then
            local ok, err = pcall(MobTooltip.OnTooltip, tooltip)
            if not ok then NS:Debug("MobTooltip: %s", tostring(err)) end
        end
    end)
end
