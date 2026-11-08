local ADDON_NAME, NS = ...

-- Marking area namespace (MK). The marking modules come from TankMarkForever almost unchanged; this file gives them
-- the namespace they were written against (db, char, L, Print, Debug, On/Fire, RegisterModule, isEnabled), backed by
-- Bulwark: settings in BulwarkDB.marking / BulwarkCharDB.marking, Bulwark's debug trace and error recorder, the
-- Marking area switch instead of TankMark's own enable flag.
local MK = {}
NS.Marking = MK
MK.version = NS.version
MK.isEnabled = false     -- true while the Marking area runs

-- Own string table (TankMark's keys clash with Bulwark's, e.g. STATUS_HEADER); missing keys fall back to the key.
MK.L = setmetatable({}, { __index = function(_, key) return key end })
local currentLocale = GetLocale and GetLocale() or "enUS"
function MK:NewLocale(locale)
    if locale == "enUS" or locale == currentLocale then return MK.L end
    return nil
end

-- Account-wide (BulwarkDB.marking).
MK.DefaultConfig = {
    overlay = true,         -- planned icons above nameplates
    shiftSelect = true,     -- Shift-hover adds a mob to the pack selection (out of combat)
    nearOnly = true,        -- plan only mobs within ~30 yd (unless a Shift-hover selection is active)
    record = true,          -- inside dungeons/raids, new mob types become database entries automatically
    -- HUD: always shown; clicking its title bar collapses it. point = { x, y } of the top-left corner, nil = default;
    -- locked = true: the title bar doesn't drag.
    hud = { collapsed = false },
    -- Learned mobs, per zone: [zone] = { names = { [name] = entry }, sigs = { [signature] = entry } }
    -- entry = { prio = 1-9, type = "TANK"|"CC"|"IGNORE", icon = 1-8 (optional fixed icon), class, note, levels }
    mobs = {},
    keysMoved = false,      -- the old TankMarkForever key bindings were moved to Bulwark's buttons (Keys.lua)
}

-- Per character (BulwarkCharDB.marking): each character has its own group, so its own team setup.
-- rows = kill order (top first). role: "TANK" (optionally owned by a tank), "CC" (needs a player in the group) or
-- "FOLLOW" (the player wears the mark; not on skull); off = true: switched off in the HUD; player = "First Last".
MK.DefaultCharConfig = {
    setup = {
        rows = {
            { icon = 8, role = "TANK" }, { icon = 7, role = "TANK" }, { icon = 6, role = "TANK" },
            { icon = 5, role = "TANK" }, { icon = 4, role = "TANK" }, { icon = 3, role = "TANK" },
            { icon = 2, role = "TANK" }, { icon = 1, role = "TANK" },
        },
    },
}
NS.DefaultConfig.marking = MK.DefaultConfig
NS.DefaultCharConfig.marking = MK.DefaultCharConfig
MK.CopyTable = NS.CopyTable

function MK:Print(msg, ...) NS:Print(msg, ...) end
function MK:Debug(msg, ...) NS:Debug(msg, ...) end
function MK:On(message, fn) NS:On(message, fn) end
function MK:Fire(message, ...) NS:Fire(message, ...) end
MK.Trap = NS.Trap

-- Marking modules are Bulwark modules of the "marking" area, also reachable as MK.<name>.
function MK:RegisterModule(name)
    local module = NS:RegisterModule("Mark" .. name, "marking")
    MK[name] = module
    return module
end

function MK:Get(key)
    local value = MK.db and MK.db[key]
    if value ~= nil then return value end
    return MK.DefaultConfig[key]
end

function MK:Set(key, value)
    if MK.db then MK.db[key] = value end
end

-- Learned mobs for one zone (created on demand).
function MK:GetZoneMobs(zone)
    local all = MK.db.mobs
    if not all[zone] then all[zone] = { names = {}, sigs = {} } end
    return all[zone]
end

-- Registered before every other Marking module, so it initializes, enables and disables first.
local Core = MK:RegisterModule("Core")

function Core:OnInitialize()
    MK.db = NS.db.marking
    MK.char = NS.char.marking
end

function Core:OnEnable()
    MK.isEnabled = true
end

function Core:OnDisable()
    MK.isEnabled = false
end
