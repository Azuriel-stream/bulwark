local ADDON_NAME, NS = ...
local MK = NS.Marking

-- The learned-mob database: per zone, entries by name (open world) or by signature (instances, where names are
-- secret). entry = { type = "TANK"|"CC"|"IGNORE" (which kind of mark it prefers; IGNORE = no mark), prio = 1-9, icon = 1-8 or nil, class = CC class or nil,
-- note = player-given label for a signature }
local MobDB = MK:RegisterModule("MobDB")
local L, Rules = MK.L, MK.Rules

MobDB.TYPES = { "TANK", "CC", "IGNORE" }
MobDB.CC_CLASSES = { "MAGE", "ROGUE", "WARLOCK", "HUNTER", "PRIEST", "DRUID" }

local function NextIn(list, current)
    for i, v in ipairs(list) do
        if v == current then return list[i + 1] end
    end
    return list[1]
end

-- "14|elite|MANA" or "14|elite|MANA|126239" -> level, tier, power, model file ID
-- Signature forms (Rules.Signature): "elite|RAGE|126512" (model, level-free), "14|elite|RAGE" (no model) and the
-- short-lived "14|elite|RAGE|126512" (model + level, migrated at load). Returns level (nil for model sigs), tier, power, model.
function MobDB.ParseSig(sig)
    local parts = { strsplit("|", sig or "") }
    if tonumber(parts[1]) then
        return tonumber(parts[1]), parts[2], parts[3], tonumber(parts[4])
    end
    return nil, parts[1], parts[2], tonumber(parts[3])
end

function MobDB.ModelName(model)
    if not model then return nil end
    return (MK.ModelNames and MK.ModelNames[model]) or ("model " .. model)
end

-- Readable label for a signature: "elite worm melee", or "lvl 14 elite caster" without a model
function MobDB.DescribeSig(sig)
    local level, tier, power, model = MobDB.ParseSig(sig)
    local role = L["ROLE_" .. Rules.RoleFromPower(power)]
    local body = MobDB.ModelName(model)
    if body then
        return string.format("%s %s %s", tier or "?", body, role)
    end
    local lvl = (not level or level == -1) and "??" or tostring(level)
    return string.format("lvl %s %s %s", lvl, tier or "?", role)
end

-- Levels a model entry has been seen at: "13-15", "14" or nil
function MobDB.LevelText(entry)
    local lv = entry and entry.levels
    if not lv or not lv[1] then return nil end
    if lv[1] == lv[2] then return tostring(lv[1]) end
    return lv[1] .. "-" .. lv[2]
end

function MobDB.NoteLevel(entry, level)
    if not entry or type(level) ~= "number" or level <= 0 then return end
    local lv = entry.levels
    if not lv then
        entry.levels = { level, level }
    elseif level < lv[1] then
        lv[1] = level
    elseif level > lv[2] then
        lv[2] = level
    end
end

-- Zones that have entries, sorted, plus `include` (the current zone) even if empty.
function MobDB:Zones(include)
    local list, seen = {}, {}
    for zone, data in pairs(MK.db.mobs) do
        if next(data.names) or next(data.sigs) then
            table.insert(list, zone)
            seen[zone] = true
        end
    end
    if include and include ~= "" and not seen[include] then table.insert(list, include) end
    table.sort(list)
    return list
end

-- The instance map of a zone (keys Data/InstanceMobs.lua): remembered while you're there, so the window can name
-- entries of other zones too.
function MobDB.InstanceOf(zone)
    local data = MK.db.mobs[zone]
    if data and data.instanceID then return data.instanceID end
    if zone == MK.Plates.zone then return MK.Plates.instanceID end
    return nil
end

function MobDB.RememberInstance()
    local id, data = MK.Plates.instanceID, MK.db and MK.db.mobs[MK.Plates.zone]
    if data and id and MK.InstanceMobs[id] then data.instanceID = id end
end

-- NPC names the offline data gives for a model signature entry (power type, boss or not, levels seen), or nil.
function MobDB.DataNames(zone, sig, entry)
    local level, tier, power, model = MobDB.ParseSig(sig)
    local id = MobDB.InstanceOf(zone)
    local variants = id and model and MK.InstanceMobs[id] and MK.InstanceMobs[id][model]
    if not variants then return nil end
    local lo, hi = level, level
    if entry and entry.levels then lo, hi = entry.levels[1], entry.levels[2] end
    local names = Rules.NamesFromData(variants, power, lo, hi, tier == "boss")
    return #names > 0 and names or nil
end

-- Default label of a signature entry: "Ragefire Trogg", "Searing Blade Cultist +2", else "elite troglodyte melee".
function MobDB.DefaultLabel(zone, sig, entry)
    local names = MobDB.DataNames(zone, sig, entry)
    if not names then return MobDB.DescribeSig(sig) end
    if #names == 1 then return names[1] end
    return string.format("%s +%d", names[1], #names - 1)
end

-- Entries of a zone as rows { kind = "name"|"sig", key, entry, label }: names A-Z, then signatures by level (high first).
function MobDB:Entries(zone)
    local data = MK.db.mobs[zone]
    local rows = {}
    if not data then return rows end
    for name, entry in pairs(data.names) do
        table.insert(rows, { kind = "name", key = name, entry = entry, label = name })
    end
    for sig, entry in pairs(data.sigs) do
        table.insert(rows, { kind = "sig", key = sig, entry = entry, label = entry.note or MobDB.DefaultLabel(zone, sig, entry) })
    end
    -- Signatures by level, high first: model entries by the highest level seen.
    local function SortLevel(row)
        local level = MobDB.ParseSig(row.key)
        return level or (row.entry.levels and row.entry.levels[2]) or 0
    end
    table.sort(rows, function(a, b)
        if a.kind ~= b.kind then return a.kind == "name" end
        if a.kind == "name" then return a.key < b.key end
        local la, lb = SortLevel(a), SortLevel(b)
        if la ~= lb then return la > lb end
        return a.key < b.key
    end)
    return rows
end

local function Changed()
    MK:Fire("MOBDB_CHANGED")
    if MK.Plates then MK.Plates.Changed() end
end

-- Learn a unit: by name where readable, by signature otherwise. Default priority from the rules (power x tier).
-- Returns the stored entry and a label, or nil if the unit isn't an attackable mob.
function MobDB:Learn(unit, entry)
    local ok, canAttack = pcall(UnitCanAttack, "player", unit)
    if not UnitExists(unit) or not ok or MK.Utils.IsSecret(canAttack) or canAttack ~= true then return nil end
    local rec = MK.Plates:RecordFor(unit) or MK.Plates:Read(unit, {})
    local zone = MK:GetZoneMobs(MK.Plates.zone)
    MobDB.RememberInstance()
    if not entry then
        entry = { type = "TANK", prio = Rules.RoleTierPrio(Rules.RoleFromPower(rec.power), rec.tier) }
    end
    local label
    if rec.name then
        zone.names[rec.name] = entry
        label = rec.name
    else
        zone.sigs[rec.sig] = entry
        if rec.model then MobDB.NoteLevel(entry, rec.level) end
        label = MobDB.DefaultLabel(MK.Plates.zone, rec.sig, entry)
    end
    Changed()
    return entry, label, rec
end

-- Entries saved before the Tank/CC naming: type "KILL" is now "TANK" (the kind of mark the mob prefers).
function MobDB.MigrateTypes(mobs)
    for _, data in pairs(mobs) do
        for _, list in pairs({ data.names or {}, data.sigs or {} }) do
            for _, entry in pairs(list) do
                if entry.type == "KILL" then entry.type = "TANK" end
            end
        end
    end
end

-- One-time conversion of "level|tier|power|model" keys (identity step 1) to the level-free "tier|power|model".
-- Entries that only differed by level merge: the first one (by key) is kept. Returns the merged labels.
function MobDB:MigrateModelSigs()
    local merged = {}
    for _, data in pairs(MK.db.mobs) do
        local old = {}
        for sig in pairs(data.sigs) do
            local level, tier, power, model = MobDB.ParseSig(sig)
            if level and model then table.insert(old, sig) end
        end
        table.sort(old)
        for _, sig in ipairs(old) do
            local level, tier, power, model = MobDB.ParseSig(sig)
            local entry = data.sigs[sig]
            data.sigs[sig] = nil
            local key = Rules.Signature(level, tier, power, model)
            if data.sigs[key] then
                table.insert(merged, MobDB.DescribeSig(key))
            else
                data.sigs[key] = entry
            end
            MobDB.NoteLevel(data.sigs[key], level)
        end
    end
    return merged
end

-- Recorder (legacy Flight Recorder): inside instances, every new mob type the plates show out of combat becomes a
-- Tank entry with the rules' default priority, so the database fills up as you go and only needs tuning. Keyed like
-- Learn (name if readable, else the model signature); waits for the model, so no level-based fallback entries.
-- Nothing is overwritten. One chat line per new entry. Returns the number recorded.
function MobDB:RecordVisible()
    local Plates = MK.Plates
    if not MK:Get("record") or not Plates.inInstance or InCombatLockdown() then return 0 end
    local zone, added = nil, 0
    for _, rec in pairs(Plates.records) do
        if rec.hostile and not rec.player and not rec.dead and rec.markable and rec.ctype ~= "Critter"
            and (rec.name or rec.model) then
            zone = zone or MK:GetZoneMobs(Plates.zone)
            local list, key = zone.sigs, rec.sig
            if rec.name then list, key = zone.names, rec.name end
            if not list[key] then
                local entry = { type = "TANK", prio = Rules.RoleTierPrio(Rules.RoleFromPower(rec.power), rec.tier) }
                list[key] = entry
                if not rec.name then MobDB.NoteLevel(entry, rec.level) end
                added = added + 1
                MK:Print(L["RECORDED"], rec.name or MobDB.DefaultLabel(Plates.zone, key, entry), entry.prio)
            end
        end
    end
    if added > 0 then
        MobDB.RememberInstance()
        MK:Fire("MOBDB_CHANGED")   -- the plan doesn't change: the entries carry the rules' priorities
    end
    return added
end

-- =========================================================================
-- Real names in instances (Learn.lua: the %t echo when you target a mob, the damage meter after a pull).
-- A name entry is added only when the zone has none for that name. Its settings are copied from the body
-- (signature) entry the mob matched, so your tuning carries over; with no body entry it gets the rules' default,
-- but only while recording is on. Existing entries are never changed or deleted: body entries stay as the fallback
-- for mobs whose name isn't known yet (not targeted this visit), and they still cover the other mobs sharing the body.
-- =========================================================================
local INHERIT = { "type", "prio", "icon", "class" }   -- not the note (a label for the body) or the levels

-- The client's placeholder for a name it couldn't resolve (Maraudon had an "Unknown" mob, 2026-11-27): never a mob.
function MobDB.IsUnknownName(name)
    return name == "Unknown" or (UNKNOWNOBJECT ~= nil and name == UNKNOWNOBJECT) or (UNKNOWN ~= nil and name == UNKNOWN)
end

-- name; sigs: the signatures the mob may have, best first (a plate's sig + sigBase; from the data, every body the
-- name uses: 138 of 976 names have more than one, e.g. male and female models); the first with an entry is copied.
-- defaultPrio: rules' priority if nothing to copy. Returns the new entry, or nil if nothing was added.
function MobDB:AdoptName(name, sigs, defaultPrio, level)
    if type(name) ~= "string" or name == "" or MobDB.IsUnknownName(name) or not MK.Plates.inInstance then return nil end
    local zone = MK:GetZoneMobs(MK.Plates.zone)
    if zone.names[name] then return nil end
    local bodyKey
    for _, sig in ipairs(sigs or {}) do
        if zone.sigs[sig] then bodyKey = sig; break end
    end
    local entry
    if bodyKey then
        entry = {}
        for _, k in ipairs(INHERIT) do entry[k] = zone.sigs[bodyKey][k] end
    elseif MK:Get("record") and defaultPrio then
        entry = { type = "TANK", prio = defaultPrio }
    else
        return nil
    end
    zone.names[name] = entry
    MobDB.NoteLevel(entry, level)
    MobDB.RememberInstance()
    if bodyKey then
        MK:Print(L["NAMED_FROM_BODY"], name, tonumber(entry.prio) or 0,
            zone.sigs[bodyKey].note or MobDB.DefaultLabel(MK.Plates.zone, bodyKey, zone.sigs[bodyKey]))
    else
        MK:Print(L["RECORDED"], name, entry.prio)
    end
    MK:Fire("MOBDB_CHANGED")
    return entry
end

-- A plate's name was learned: add its name entry (settings from the body entry it matched).
local function OnLearned(rec)
    if not rec or not rec.learnedName then return end
    MobDB:AdoptName(rec.learnedName, { rec.sig, rec.sigBase },
        Rules.RoleTierPrio(Rules.RoleFromPower(rec.power), rec.tier), rec.level)
end

function MobDB:OnInitialize()
    MobDB.MigrateTypes(MK.db.mobs)
    local merged = MobDB:MigrateModelSigs()
    if #merged > 0 then
        C_Timer.After(5, function() MK:Print(L["MOBS_MERGED"], table.concat(merged, ", ")) end)
    end
    MK:On("PLATES_CHANGED", function() MobDB:RecordVisible() end)
    MK:On("MOB_LEARNED", OnLearned)
end

-- Forget the entry a unit would match. Returns its label or nil.
function MobDB:ForgetUnit(unit)
    if not UnitExists(unit) then return nil end
    local rec = MK.Plates:RecordFor(unit) or MK.Plates:Read(unit, {})
    local zone = MK:GetZoneMobs(MK.Plates.zone)
    if rec.name and zone.names[rec.name] then
        zone.names[rec.name] = nil
        Changed()
        return rec.name
    end
    -- The model-specific entry first, then the model-less one it falls back to.
    for _, sig in ipairs({ rec.sig, rec.sigBase }) do
        if not rec.name and sig and zone.sigs[sig] then
            zone.sigs[sig] = nil
            Changed()
            return MobDB.DescribeSig(sig)
        end
    end
    return nil
end

-- =========================================================================
-- Editing one entry (mob database window)
-- =========================================================================
function MobDB:CycleType(entry)
    entry.type = NextIn(MobDB.TYPES, entry.type) or "TANK"
    if entry.type ~= "IGNORE" and not entry.prio then entry.prio = 5 end
    Changed()
end

function MobDB:StepPrio(entry, delta)
    entry.prio = math.max(1, math.min(9, (tonumber(entry.prio) or 5) + delta))
    Changed()
end

-- From the dropdowns: icon 1-8 or nil (auto); class from CC_CLASSES or nil (any).
function MobDB:SetIcon(entry, icon)
    entry.icon = icon
    Changed()
end

function MobDB:SetClass(entry, class)
    entry.class = class
    Changed()
end

function MobDB:ClearIcon(entry)
    entry.icon = nil
    Changed()
end

function MobDB:SetNote(entry, note)
    note = note and strtrim(note) or ""
    entry.note = note ~= "" and note or nil
    Changed()
end

function MobDB:Delete(zone, kind, key)
    local data = MK.db.mobs[zone]
    if not data then return end
    if kind == "name" then data.names[key] = nil else data.sigs[key] = nil end
    Changed()
end

-- The label shown in plans and overlays for a plate record: its name (readable, or learned from the %t echo), the
-- player's note on its signature, or the generic description.
function MobDB:Label(rec, zone)
    if rec.name then return rec.name end
    if rec.learnedName then return rec.learnedName end
    local data = MK.db and MK.db.mobs[zone or MK.Plates.zone]
    local entry = data and (data.sigs[rec.sig] or (rec.sigBase and data.sigs[rec.sigBase]))
    return (entry and entry.note) or rec.dataName or MobDB.DescribeSig(rec.sig)
end
