-- Shared test setup: models the APIs wowsim doesn't (power type, classification, nameplate frames, free icons).
local H = {}

-- A mob record as Plates:Read builds it (for pure planner tests).
function H.rec(token, opts)
    opts = opts or {}
    return {
        token = token, seq = opts.seq or tonumber(token:match("%d+")) or 0,
        name = opts.name, level = opts.level or 15, tier = opts.tier or "elite",
        power = opts.power or "RAGE", ctype = opts.ctype,
        sig = string.format("%s|%s|%s", tostring(opts.level or 15), opts.tier or "elite", opts.power or "RAGE"),
    }
end

-- Install API models on a fresh sim (call from t.fresh setup, before the addon loads).
function H.install(s)
    local env = s.env
    s.zone = s.zone or "Test Zone"
    s.shift = false
    local function U(u) return s.units[u] end
    env.UnitPowerType = function(u)
        local x = U(u)
        if not x then return 0, "MANA" end
        return x.power == "MANA" and 0 or 1, x.power or "RAGE"
    end
    env.UnitClassification = function(u) local x = U(u); return x and x.tier or "normal" end
    env.UnitIsBossMob = function(u) local x = U(u); return x and x.boss or false end
    env.UnitCreatureType = function(u) local x = U(u); return x and x.ctype or nil end
    env.CanBeRaidTarget = function(u) return U(u) ~= nil end
    env.GetRealZoneText = function() return s.zone end
    -- Range: units[u].far = beyond 30 yd (the range item and the 28 yd interact check say so).
    env.C_Item = env.C_Item or {}
    env.C_Item.IsItemInRange = function(_, u) local x = U(u); if x then return not x.far end end
    env.C_Item.RequestLoadItemDataByID = function() end
    env.CheckInteractDistance = function(u) local x = U(u); if x then return not x.far end end
    -- Line of sight: Forever's default nameplate fade CVars (in-game LOS probe); units[u].hidden = behind terrain.
    s.cvars.nameplateOccludedAlphaMult, s.cvars.nameplateMinAlpha, s.cvars.nameplateMaxAlpha = "0.400000", "0.600000", "1.000000"
    env.IsInInstance = function() return false, "none" end
    env.IsShiftKeyDown = function() return s.shift end
    env.UnitAffectingCombat = function(u) local x = U(u); return x and x.inCombat or false end
    -- Free icons: the lowest index >= start that no unit wears (with the flag, icons on dead units count as free).
    env.GetNextAvailableRaidTargetMarkerIndex = function(start, _, _, deadAreFree)
        local worn = {}
        for _, x in pairs(s.units) do
            if x.raidTarget and not (deadAreFree and x.dead) then worn[x.raidTarget] = true end
        end
        for i = start, 8 do if not worn[i] then return i end end
        return 0
    end
    -- Model scenes: an actor "loads" units[u].model at once and fires the loaded callback (s.modelsBlocked: as if
    -- Blizzard closed the loophole, GetModelFileID returns 0).
    local origCreateFrame = env.CreateFrame
    env.CreateFrame = function(frameType, ...)
        if frameType ~= "ModelScene" then return origCreateFrame(frameType, ...) end
        local scene = { SetSize = function() end, SetPoint = function() end, SetAlpha = function() end }
        function scene.CreateActor()
            local actor = { model = 0 }
            function actor.ClearModel(a) a.model = 0 end
            function actor.SetOnModelLoadedCallback(a, cb) a.cb = cb end
            function actor.SetModelByUnitCreatureDisplayID(a, unit)
                local x = U(unit)
                a.model = (x and not s.modelsBlocked and x.model) or 0
                if a.cb then a.cb(a) end
                return true
            end
            function actor.GetModelFileID(a) return a.model end
            return actor
        end
        return scene
    end
    -- Nameplate frames: RaidTargetFrame shown when the unit wears an icon.
    env.C_NamePlate = env.C_NamePlate or {}
    env.C_NamePlate.GetNamePlateForUnit = function(u)
        if not U(u) then return nil end
        return { GetAlpha = function() return U(u).hidden and 0.24 or 1 end,
                 UnitFrame = { RaidTargetFrame = { IsShown = function() return U(u).raidTarget ~= nil end } } }
    end
end

-- Three hostile plates: an elite caster, two elite melee.
function H.pack(s)
    s.units.nameplate1 = { name = "Ragefire Trogg", guid = "Creature-0-1-0-1-11318-0000000001", friendly = false,
                           level = 14, tier = "elite", power = "RAGE", ctype = "Humanoid" }
    s.units.nameplate2 = { name = "Ragefire Shaman", guid = "Creature-0-1-0-1-11319-0000000002", friendly = false,
                           level = 13, tier = "elite", power = "MANA", ctype = "Humanoid" }
    s.units.nameplate3 = { name = "Ragefire Trogg", guid = "Creature-0-1-0-1-11318-0000000003", friendly = false,
                           level = 15, tier = "elite", power = "RAGE", ctype = "Humanoid" }
    s.units.target = nil
end

-- Opens the Bulwark window on a Marking page and returns that page (its widgets: rows, boxes, ...).
function H.page(s, key)
    local NS = s.env.Bulwark
    NS.Window:Open("marking", key)
    for _, p in ipairs(NS:GetArea("marking").pages) do
        if p.key == key then return p end
    end
end

return H
