local ADDON_NAME, NS = ...

-- The only global besides the SavedVariables, SLASH_* and the compartment callback.
_G["Bulwark"] = NS

NS.name = ADDON_NAME
NS.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.1.0"
NS.modules = {}
NS.moduleOrder = {}
NS.isInitialized = false

local eventFrame = CreateFrame("Frame", "Bulwark_EventFrame")

-- Blocked-action recorder: keeps the last blocked/forbidden action blamed on Bulwark for /bwk debug.
local securityFrame = CreateFrame("Frame", "Bulwark_SecurityFrame")
pcall(securityFrame.RegisterEvent, securityFrame, "ADDON_ACTION_BLOCKED")
pcall(securityFrame.RegisterEvent, securityFrame, "ADDON_ACTION_FORBIDDEN")
securityFrame:SetScript("OnEvent", function(_, event, addonName, functionName)
    if addonName ~= ADDON_NAME then return end
    local stack = (debugstack and debugstack(2, 8, 8)) or "No stack available"
    if NS.db then
        NS.db.lastBlocked = { event = event, func = tostring(functionName), stack = stack, time = date("%Y-%m-%d %H:%M:%S") }
    end
    NS:RecordError(event .. ": " .. tostring(functionName) .. " (" .. ADDON_NAME .. ")", stack)
end)

-- Chat output: print() with a gold prefix (never DEFAULT_CHAT_FRAME, see kb/gotchas.md).
function NS:Print(msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    print("|cffD9AA3C[Bulwark]|r " .. tostring(msg))
end

-- Debug trace: printed and kept in BulwarkDB.debugLog (read it from SavedVariables after a /reload).
local DEBUG_LOG_MAX = 400
function NS:Debug(msg, ...)
    if not (NS.db and NS.db.debug) then return end
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    print("|cff888888[BWK]|r " .. msg)
    local log = NS.db.debugLog
    table.insert(log, date("%H:%M:%S") .. (InCombatLockdown() and " [combat] " or " ") .. msg)
    while #log > DEBUG_LOG_MAX do table.remove(log, 1) end
end

-- Client-wide diagnostics (Lua error popups, Logs\taint.log). These CVars persist, so they only change on request.
function NS:SetDebugCVars(enabled)
    NS.db.debugCVars = enabled and true or false
    pcall(SetCVar, "scriptErrors", enabled and "1" or "0")
    pcall(SetCVar, "taintLog", enabled and "1" or "0")
end

-- Internal messages between modules (e.g. AREA_CHANGED -> window, settings page).
local listeners = {}
function NS:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function NS:Fire(message, ...)
    for _, fn in ipairs(listeners[message] or {}) do
        local ok, err = xpcall(fn, NS.Trap, ...)
        if not ok then
            NS:Print("|cffFF4444Error in %s handler:|r %s", message, tostring(err))
        end
    end
end

-- Modules: area = nil for core modules (always on), else the key of the area they belong to.
-- Lifecycle: OnInitialize (ADDON_LOADED, every module), OnEnable/OnDisable (login, area switch).
function NS:RegisterModule(name, area)
    local module = { name = name, area = area }
    NS.modules[name] = module
    NS[name] = module
    table.insert(NS.moduleOrder, name)
    return module
end

-- Calls method on every module of one area (area = false: core modules; nil: all modules), in registration order.
function NS:CallModules(method, area)
    for _, name in ipairs(NS.moduleOrder) do
        local mod = NS.modules[name]
        local match = (area == nil) or (area == false and mod.area == nil) or (mod.area == area)
        if match and type(mod[method]) == "function" then
            local ok, err = xpcall(mod[method], NS.Trap, mod)
            if not ok then
                NS:Print("|cffFF4444Error in %s:%s:|r %s", name, method, tostring(err))
            end
        end
    end
end

local function OnEvent(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if not NS.isInitialized then
            NS.isInitialized = true
            NS:InitConfig()
            NS:FlushErrors()
            NS:CallModules("OnInitialize")
        end
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        eventFrame:UnregisterEvent("PLAYER_LOGIN")
        local _, class = UnitClass("player")
        NS.playerClass = class
        NS:CallModules("OnEnable", false)
        NS:StartAreas()
        NS:Print(NS.L["ADDON_LOADED"], NS.version)
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", OnEvent)
