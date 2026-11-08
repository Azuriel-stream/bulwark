local ADDON_NAME, NS = ...

-- One-time import of the standalone addons' settings (TankAlertForever, TankAuditForever, TankMarkForever).
-- The client only reads an addon's own SavedVariables file, so the workspace script tools/migrate-bulwark.ps1
-- (WoW closed) appends the old files' contents to Bulwark's files, and the TOC declares the old variable names for
-- this version. Here they're copied into BulwarkDB/BulwarkCharDB once, then dropped (nil = not saved again).
-- Runs in OnInitialize of the first registered module, before the areas build anything from their settings.
local Import = NS:RegisterModule("Import")

local ALERT_KEYS = { "forceChannel", "announceCC", "announceDisarm", "alertThrottle", "quietWhenThreatSolid",
    "announceThreatWhisper", "threatWhisperThreshold", "whisperThrottle", "onlyTankWhispers" }
local AUDIT_KEYS = { "locked", "scale", "point", "checkSelf", "checkGroup", "checkConsumables", "consumableLevel",
    "checkHealthstone", "checkDebuffs", "checkUnwanted", "gratitude", "watchSound", "watchWarnSeconds",
    "watchDurations", "blessingPriority" }
local MARK_KEYS = { "overlay", "shiftSelect", "nearOnly", "record", "hud" }

local function Copy(dst, src, keys)
    for _, key in ipairs(keys) do
        if src[key] ~= nil then dst[key] = NS.CopyTable(src[key]) end
    end
end

-- Learned mobs: zones and entries Bulwark doesn't have yet are added; Bulwark's own entries win.
local function MergeMobs(dst, src)
    local added = 0
    for zone, data in pairs(src) do
        if type(data) == "table" then
            dst[zone] = dst[zone] or { names = {}, sigs = {} }
            for _, kind in ipairs({ "names", "sigs" }) do
                dst[zone][kind] = dst[zone][kind] or {}
                for key, entry in pairs(data[kind] or {}) do
                    if dst[zone][kind][key] == nil then
                        dst[zone][kind][key] = NS.CopyTable(entry)
                        added = added + 1
                    end
                end
            end
        end
    end
    return added
end

-- Returns the list of things imported (for the chat line and tests).
function Import.Run()
    local db, char = NS.db, NS.char
    db.imported = db.imported or {}
    local done, report = db.imported, {}
    local stamp = date("%Y-%m-%d")

    local taf = TankAlertForeverDB
    if type(taf) == "table" and not done.alerts then
        Copy(db.alerts, type(taf.global) == "table" and taf.global or {}, ALERT_KEYS)
        if type(taf.abilities) == "table" then db.alerts.abilities = NS.CopyTable(taf.abilities) end
        done.alerts = stamp
        table.insert(report, NS.L["AREA_ALERTS"])
    end

    local tau = TankAuditForeverDB
    if type(tau) == "table" and not done.audit then
        Copy(db.audit, tau, AUDIT_KEYS)
        done.audit = stamp
        table.insert(report, NS.L["AREA_AUDIT"])
    end

    local tmf = TankMarkForeverDB
    if type(tmf) == "table" and not done.marking then
        Copy(db.marking, tmf, MARK_KEYS)
        local mobs = type(tmf.mobs) == "table" and MergeMobs(db.marking.mobs, tmf.mobs) or 0
        done.marking = stamp
        table.insert(report, string.format(NS.L["IMPORT_MOBS"], NS.L["AREA_MARKING"], mobs))
    end

    local tmfChar = TankMarkForeverCharDB
    if type(tmfChar) == "table" and type(tmfChar.setup) == "table" and not char.importedSetup then
        char.marking.setup = NS.CopyTable(tmfChar.setup)
        char.importedSetup = stamp
        table.insert(report, NS.L["IMPORT_TEAM"])
    end

    -- Imported (or imported before): drop the old copies so they aren't written into Bulwark's files again.
    TankAlertForeverDB, TankAuditForeverDB, TankMarkForeverDB, TankMarkForeverCharDB = nil, nil, nil, nil
    return report
end

function Import:OnInitialize()
    local report = Import.Run()
    if #report > 0 then
        -- Printed after login, when chat is up.
        C_Timer.After(3, function() NS:Print(NS.L["IMPORT_DONE"], table.concat(report, ", ")) end)
    end
end
