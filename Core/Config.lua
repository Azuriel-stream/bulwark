local ADDON_NAME, NS = ...

-- Account-wide settings (BulwarkDB). Each area adds its own sub-table (NS.DefaultConfig.<areaKey>) when it's ported;
-- the on/off switches live in areas.<key>.enabled (filled in by NS:RegisterArea).
NS.DefaultConfig = {
    areas = {},
    ui = {
        scale = 1,          -- window scale (0.6 - 1.4)
        -- x, y: window top-left in the window's own coordinates (nil = centered)
    },
    minimap = {
        hide = false,
        angle = 225,        -- degrees around the minimap, 0 = east, counter-clockwise
    },
    debug = false,          -- debug trace in chat + debugLog
    debugCVars = false,     -- scriptErrors/taintLog CVars set by /bwk debug cvars
    debugLog = {},
    errors = {},
}

-- Per-character settings (BulwarkCharDB).
NS.DefaultCharConfig = {
    lastTab = nil,          -- area key the window opens on
    lastPage = {},          -- [areaKey] = page key
}

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = CopyTable(v)
    end
    return copy
end
NS.CopyTable = CopyTable

-- Fills in missing defaults recursively without overwriting the user's values.
local function MergeDefaults(target, source)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = CopyTable(v)
        elseif type(target[k]) == "table" and type(v) == "table" then
            MergeDefaults(target[k], v)
        end
    end
end
NS.MergeDefaults = MergeDefaults

function NS:InitConfig()
    if type(BulwarkDB) ~= "table" then BulwarkDB = {} end
    MergeDefaults(BulwarkDB, NS.DefaultConfig)
    if type(BulwarkCharDB) ~= "table" then BulwarkCharDB = {} end
    MergeDefaults(BulwarkCharDB, NS.DefaultCharConfig)
    BulwarkDB.version = NS.version
    NS.db = BulwarkDB
    NS.char = BulwarkCharDB
end
