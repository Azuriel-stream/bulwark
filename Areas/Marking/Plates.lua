local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Tracks hostile nameplates and what can be read about each mob. A nameplateN token stays bound to its mob while
-- the plate is shown, so a record read out of combat stays valid in combat until NAME_PLATE_UNIT_REMOVED.
local Plates = MK:RegisterModule("Plates")
local Utils, Rules = MK.Utils, MK.Rules

Plates.records = {}    -- [token] = record (see Read)
Plates.selected = {}   -- [token] = hover order (1, 2, ...): Shift-hover pack selection
Plates.zone = ""
Plates.inInstance = false

local seq = 0
local pickSeq = 0
local changePending = false

-- Debounced: many plates arrive at once when you walk up to a pack.
local function Changed()
    if changePending then return end
    changePending = true
    C_Timer.After(0.1, function()
        changePending = false
        MK:Fire("PLATES_CHANGED")
    end)
end
Plates.Changed = Changed

local function NpcID(guid)
    if not guid then return nil end
    local _, _, _, _, _, id = strsplit("-", guid)
    return tonumber(id)
end

-- Inside instances the creature type is secret; the offline data (Data/InstanceMobs.lua: instance map + model file ->
-- the NPCs using it) restores it when every NPC matching the plate's power type and level agrees. Also gives their
-- CC immunities and names. A readable UnitCreatureType (open world) always wins. A dungeon boss (every matching NPC
-- completes an encounter) gets tier "boss": killed first, never CC'd, and its own signature instead of sharing the
-- trash entry of its body (Oggleflint vs Ragefire Trogg). Recomputes the signatures.
function Plates.Identify(rec)
    rec.ctype, rec.ctypeSource = rec.unitType, rec.unitType and "unit" or nil
    rec.tier, rec.tierSource = rec.unitTier, nil
    rec.immune, rec.dataName = nil, nil
    local mobs = Plates.instanceID and MK.InstanceMobs and MK.InstanceMobs[Plates.instanceID]
    local variants = mobs and rec.model and mobs[rec.model]
    local id = variants and Rules.IdentifyFromData(variants, rec.power, rec.level)
    if id then
        rec.immune = id.immune
        if #id.names == 1 then rec.dataName = id.names[1] end
        if not rec.ctype and id.ctype then rec.ctype, rec.ctypeSource = id.ctype, "data" end
        if id.boss and rec.tier ~= "boss" then rec.tier, rec.tierSource = "boss", "data" end
    end
    rec.sigBase = Rules.Signature(rec.level, rec.tier, rec.power)
    rec.sig = Rules.Signature(rec.level, rec.tier, rec.power, rec.model)
end

-- Everything readable about a plate. In instances name/guid/creature type are secret (nil here);
-- level, classification, power type and the boss flags stay readable (kb/addons/TankMark.md, run 4).
function Plates:Read(token, rec)
    rec = rec or {}
    if not rec.seq then
        seq = seq + 1
        rec.seq = seq
    end
    rec.token = token
    rec.name = Utils.Safe(UnitName(token), "string", nil)
    local okG, guid = pcall(UnitGUID, token)
    rec.npcID = okG and NpcID(Utils.Safe(guid, "string", nil)) or nil
    rec.level = Utils.Safe(UnitLevel(token), "number", -1)
    rec.unitTier = Utils.Safe(UnitClassification(token), "string", "normal")
    if Utils.Flag(UnitIsBossMob, token) then rec.unitTier = "boss" end
    local okP, _, powerToken = pcall(UnitPowerType, token)
    rec.power = okP and Utils.Safe(powerToken, "string", nil) or nil
    local okT, ctype = pcall(UnitCreatureType, token)
    rec.unitType = okT and Utils.Safe(ctype, "string", nil) or nil
    Plates.Identify(rec)   -- sets ctype, tier, sig, sigBase
    if not InCombatLockdown() then rec.far = Plates.IsFar(token) end
    local okA, canAttack = pcall(UnitCanAttack, "player", token)
    rec.hostile = okA and not Utils.IsSecret(canAttack) and canAttack == true
    rec.player = Utils.Flag(UnitIsPlayer, token)
    rec.markable = Utils.Flag(CanBeRaidTarget, token)
    rec.dead = Utils.Flag(UnitIsDead, token)
    return rec
end

-- =========================================================================
-- Model identity. Forever: ModelSceneActor:SetModelByUnitCreatureDisplayID isn't guarded by
-- RequiresDeclassifiedUnitIdentity (its siblings are), and GetModelFileID is readable inside instances, so the model
-- file tells a worm from a trogg even where names are secret (kb/addons/TankMark.md, run 6). If Blizzard closes this,
-- rec.model stays nil and signatures fall back to level|tier|power.
-- =========================================================================
local modelScene
local actors = {}      -- [token] = actor (one per nameplate token, reused)
local requestSeq = 0

local function ActorFor(token)
    if not modelScene then
        modelScene = CreateFrame("ModelScene", "BWK_ModelScene", UIParent)
        modelScene:SetSize(4, 4)
        modelScene:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        modelScene:SetAlpha(0.01)   -- effectively invisible; a hidden scene might not load models
    end
    if not actors[token] then
        local ok, actor = pcall(modelScene.CreateActor, modelScene, nil, "ModelSceneActorTemplate")
        if not ok or not actor then return nil end
        actors[token] = actor
    end
    return actors[token]
end

local function ApplyModel(token, rec, fileID)
    if Plates.records[token] ~= rec then return end            -- plate gone or reused meanwhile
    if Utils.IsSecret(fileID) or type(fileID) ~= "number" or fileID <= 0 or rec.model == fileID then return end
    rec.model = fileID
    Plates.Identify(rec)
    Changed()
end

function Plates:LoadModel(token, rec)
    local actor = ActorFor(token)
    if not actor then return end
    requestSeq = requestSeq + 1
    local request = requestSeq
    actor.tmfRequest = request
    pcall(actor.ClearModel, actor)   -- never read a previous mob's model
    pcall(actor.SetOnModelLoadedCallback, actor, function(a)
        if a.tmfRequest == request then
            local ok, fileID = pcall(a.GetModelFileID, a)
            if ok then ApplyModel(token, rec, fileID) end
        end
    end)
    if not pcall(actor.SetModelByUnitCreatureDisplayID, actor, token) then return end
    C_Timer.After(1.5, function()   -- in case the loaded callback doesn't fire
        if actor.tmfRequest == request and not rec.model then
            local ok, fileID = pcall(actor.GetModelFileID, actor)
            if ok then ApplyModel(token, rec, fileID) end
        end
    end)
end

-- The plate record of a unit (mouseover/target), so learning uses the loaded model. nil if it has no plate.
function Plates:RecordFor(unit)
    if Plates.records[unit] then return Plates.records[unit] end
    for token, rec in pairs(Plates.records) do
        local ok, same = pcall(UnitIsUnit, unit, token)
        if ok and not Utils.IsSecret(same) and same == true then return rec end
    end
    return nil
end

-- Whether Blizzard's nameplate shows a raid icon. The icon itself is secret, IsShown isn't (run 2).
function Plates:IsMarked(token)
    local ok, shown = pcall(function()
        local plate = C_NamePlate.GetNamePlateForUnit(token)
        local rt = plate and plate.UnitFrame and plate.UnitFrame.RaidTargetFrame
        return rt and rt:IsShown()
    end)
    return ok and not Utils.IsSecret(shown) and shown == true
end

function Plates:CountSelected()
    local n = 0
    for _ in pairs(Plates.selected) do n = n + 1 end
    return n
end

function Plates:ClearSelection(quiet)
    if next(Plates.selected) == nil then return end
    wipe(Plates.selected)
    if not quiet then MK:Print(MK.L["SELECT_CLEARED"]) end
    Changed()
end

-- Why the planner leaves a plate out (a SKIP_* locale key), or nil if it's a candidate: hostile, alive, markable
-- NPCs not already fighting; only the selection if any.
function Plates:Exclusion(token, rec)
    if rec.player then return "SKIP_PLAYER" end
    if not rec.hostile then return "SKIP_FRIENDLY" end
    if rec.dead then return "SKIP_DEAD" end
    if not rec.markable then return "SKIP_UNMARKABLE" end
    if next(Plates.selected) ~= nil and not Plates.selected[token] then return "SKIP_SELECTION" end
    if Utils.Flag(UnitAffectingCombat, token) then return "SKIP_COMBAT" end
    if MK:Get("nearOnly") and next(Plates.selected) == nil then
        if rec.far then return "SKIP_FAR" end
        if rec.hidden then return "SKIP_HIDDEN" end
    end
    return nil
end

-- Candidates for the planner (by plate order), and { {rec, reason} } for the plates left out.
function Plates:GetCandidates()
    local list, skipped = {}, {}
    for token, rec in pairs(Plates.records) do
        local reason = Plates:Exclusion(token, rec)
        rec.pick = Plates.selected[token] -- hover order: the planner's tie-break among equal-priority mobs
        if reason then
            table.insert(skipped, { rec = rec, reason = reason })
        else
            table.insert(list, rec)
        end
    end
    table.sort(list, function(a, b) return a.seq < b.seq end)
    return list, skipped
end

local function RefreshZone()
    Plates.zone = GetRealZoneText() or ""
    Plates.inInstance = IsInInstance() == true
    -- The instance's map ID keys Data/InstanceMobs.lua (8th return; no secret annotation in the docs).
    local ok, instanceID = pcall(function() return select(8, GetInstanceInfo()) end)
    Plates.instanceID = ok and Utils.Safe(instanceID, "number", nil) or nil
    if MK.MobDB then MK.MobDB.RememberInstance() end
end

local function RereadAll()
    for token, rec in pairs(Plates.records) do
        if UnitExists(token) then Plates:Read(token, rec) else Plates.records[token] = nil end
    end
end

-- Shift-hover: add the mouseover mob to the pack selection (UnitIsUnit stays readable in dungeons, run 3).
local function OnMouseover()
    if not MK:Get("shiftSelect") or not IsShiftKeyDown() or InCombatLockdown() then return end
    for token, rec in pairs(Plates.records) do
        local ok, same = pcall(UnitIsUnit, "mouseover", token)
        if ok and not Utils.IsSecret(same) and same == true then
            if rec.hostile and not Plates.selected[token] then
                pickSeq = pickSeq + 1
                Plates.selected[token] = pickSeq
                MK:Print(MK.L["SELECT_ADDED"], Plates:CountSelected())
                Changed()
            end
            return
        end
    end
end

local frame = CreateFrame("Frame", "BWK_PlatesFrame")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        Plates.records[unit] = Plates:Read(unit)
        Plates:LoadModel(unit, Plates.records[unit])
        if InCombatLockdown() then MK:Debug("plate added %s (%s)", unit, MK.Planner.Describe(Plates.records[unit])) end
        Changed()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if InCombatLockdown() then MK:Debug("plate removed %s", unit) end
        -- A corpse's plate can go before UNIT_HEALTH told us; the record lives on in Planner.placed.
        local rec = Plates.records[unit]
        if rec and not rec.dead and Utils.Flag(UnitIsDead, unit) then rec.dead = true end
        Plates.records[unit] = nil
        Plates.selected[unit] = nil
        Changed()
    elseif event == "UNIT_HEALTH" then
        local rec = Plates.records[unit]
        if rec and not rec.dead and Utils.Flag(UnitIsDead, unit) then
            rec.dead = true
            MK:Debug("died %s%s", unit, MK.Planner.MarkOf(rec) and (" (our mark " .. MK.Planner.MarkOf(rec) .. ")") or "")
            Changed()
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        OnMouseover()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Names hidden in combat may be readable again (open world).
        RereadAll()
        Changed()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        RefreshZone()
        wipe(Plates.selected)
        Changed()
    end
end)

-- =========================================================================
-- Distance (kb/addons/TankMark.md, distance probe): exact distance and positions are blank for mobs, but range
-- checks answer inside instances out of combat, in steps. The cap is the 30 yd range item (Large Rope Net); the
-- ~28 yd interact check is the fallback. nil = unknown, never excluded. Only player -> mob is measurable, so a far
-- pack is told apart from a near one, not one pack from another at the same distance (Shift-hover does that).
-- =========================================================================
local RANGE_ITEM = 835
function Plates.IsFar(token)
    local ok, inRange = pcall(C_Item.IsItemInRange, RANGE_ITEM, token)
    if ok and not Utils.IsSecret(inRange) and type(inRange) == "boolean" then return not inRange end
    ok, inRange = pcall(CheckInteractDistance, token, 4)
    if ok and not Utils.IsSecret(inRange) and type(inRange) == "boolean" then return not inRange end
    return nil
end

-- Line of sight (kb/addons/TankMark.md, LOS probe): there's no LOS API, but the engine fades the plate of a mob hidden
-- behind terrain: plate alpha = distance alpha (nameplateMinAlpha..MaxAlpha) x nameplateOccludedAlphaMult. With the
-- defaults (0.6..1 x 0.4) hidden plates read 0.24-0.40 and visible ones 0.60-1.00, so a cut between the bands tells
-- them apart. nil = can't tell (CVars changed so the bands overlap, or the alpha isn't readable): never excluded.
local function CVarNumber(name, fallback)
    local ok, v = pcall(C_CVar.GetCVar, name)
    v = ok and not Utils.IsSecret(v) and tonumber(v)
    return v or fallback
end

function Plates.IsHidden(token)
    local mult = CVarNumber("nameplateOccludedAlphaMult", 1)
    local visibleMin = CVarNumber("nameplateMinAlpha", 0.6)
    local hiddenMax = CVarNumber("nameplateMaxAlpha", 1) * mult
    if hiddenMax >= visibleMin - 0.1 then return nil end
    -- With a target, other plates may be dimmed further (nameplateNotSelectedAlpha, if the client has it).
    local okT, isTarget = pcall(UnitIsUnit, token, "target")
    if UnitExists("target") and not (okT and isTarget == true) then
        local f = CVarNumber("nameplateNotSelectedAlpha", 1)
        visibleMin, hiddenMax = visibleMin * f, hiddenMax * f
    end
    local ok, alpha = pcall(function() return C_NamePlate.GetNamePlateForUnit(token):GetAlpha() end)
    if not ok or Utils.IsSecret(alpha) or type(alpha) ~= "number" then return nil end
    return alpha < (hiddenMax + visibleMin) / 2
end

-- Out of combat, every 0.5 s: re-check range and line of sight so the plan follows you to the next pack. (Line of
-- sight only here, not on plate add: a new plate may still be fading in.)
local function CheckRanges()
    if InCombatLockdown() or not MK:Get("nearOnly") then return end
    local changed = false
    for token, rec in pairs(Plates.records) do
        local far, hidden = Plates.IsFar(token), Plates.IsHidden(token)
        if far ~= rec.far or hidden ~= rec.hidden then
            rec.far, rec.hidden = far, hidden
            changed = true
        end
    end
    if changed then Changed() end
end
local rangeTicker

function Plates:OnEnable()
    RefreshZone()
    pcall(C_Item.RequestLoadItemDataByID, RANGE_ITEM)   -- the item answers range checks only once loaded
    if not rangeTicker then rangeTicker = C_Timer.NewTicker(0.5, CheckRanges) end
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    for i = 1, 40 do
        local token = "nameplate" .. i
        if UnitExists(token) then
            Plates.records[token] = Plates:Read(token)
            Plates:LoadModel(token, Plates.records[token])
        end
    end
    Changed()
end

function Plates:OnDisable()
    frame:UnregisterAllEvents()
    if rangeTicker then
        rangeTicker:Cancel()
        rangeTicker = nil
    end
    wipe(Plates.records)
    wipe(Plates.selected)
    Changed()
end
