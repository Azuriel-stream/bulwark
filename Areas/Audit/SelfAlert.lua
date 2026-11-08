local ADDON_NAME, NS = ...
local D, Utils = NS.AuditData, NS.Utils

-- In-combat warning for self buffs flagged `alert` in Data.lua (Battle Shout / Righteous Fury). The tile's Blizzard
-- slot already shows the exact countdown; the addon itself can't read it in combat, so the sound + glow are timed
-- from our own last cast (own casts aren't secret), with the real duration learned out of combat.
-- [in-game] in TankAuditForever 2026-10-05. (from TankAuditForever Modules/SelfAlert.lua)
local Alert = NS:RegisterModule("AuditSelfAlert", "audit")

local entries = {}   -- { def, idSet, tile, expiresAt, warned }
local ticker = nil
local frame = CreateFrame("Frame", "Bulwark_AuditSelfAlertFrame")

local function cfg() return NS.db.audit end

-- Out of combat the aura is readable: learn the real duration and the exact expiry.
local function SyncFromAuras()
    for _, e in ipairs(entries) do
        e.expiresAt = nil
        for _, id in ipairs(e.def.ids) do
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
            if aura and not Utils.IsSecret(aura.expirationTime) then
                if aura.duration and aura.duration > 0 then
                    cfg().watchDurations[id] = aura.duration
                end
                e.expiresAt = (aura.expirationTime and aura.expirationTime > 0) and aura.expirationTime or nil
                break
            end
        end
    end
end

local function Tick()
    local inCombat = InCombatLockdown()
    if not inCombat then SyncFromAuras() end
    local now, warn = GetTime(), cfg().watchWarnSeconds or 15
    for _, e in ipairs(entries) do
        local left = e.expiresAt and (e.expiresAt - now)
        if inCombat and left ~= nil and left <= warn then
            if not e.warned then
                e.warned = true
                e.tile.glow:Show()
                if cfg().watchSound then
                    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
                end
            end
        else
            e.warned = false
            e.tile.glow:Hide()
        end
    end
end

-- Own casts are readable in combat: restart the estimate from the cast.
function Alert:OnSpellCast(spellID)
    if Utils.IsSecret(spellID) then return end
    for _, e in ipairs(entries) do
        if e.idSet[spellID] then
            e.expiresAt = GetTime() + (cfg().watchDurations[spellID] or e.def.duration)
            e.warned = false
            e.tile.glow:Hide()
            -- Keep the tile's own expiry current so the bar can fade it out again after a recast (even in combat)
            if e.tile.item then e.tile.item.expiresAt = e.expiresAt end
        end
    end
end

frame:SetScript("OnEvent", function(_, _, _, _, spellID)
    Alert:OnSpellCast(spellID)
end)

local function BuildEntries()
    for _, def in ipairs(D.SELF[NS.playerClass] or {}) do
        local tile = def.alert and NS.AuditBar:GetTile("SELF:" .. def.key)
        if tile then
            entries[#entries + 1] = { def = def, idSet = Utils.ToSet(def.ids), tile = tile, expiresAt = nil, warned = false }
        end
    end
end

function Alert:OnEnable()
    if #entries == 0 then BuildEntries() end
    if #entries == 0 then return end
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.25, Tick)
end

function Alert:OnDisable()
    frame:UnregisterAllEvents()
    if ticker then ticker:Cancel(); ticker = nil end
    for _, e in ipairs(entries) do e.tile.glow:Hide() end
end

-- For tests
function Alert:GetEntries() return entries end
