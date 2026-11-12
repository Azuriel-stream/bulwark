local ADDON_NAME, NS = ...

-- Areas: the feature groups that each get a tab (Alerts, Audit, Marking) plus the Settings tab.
-- An area has an on/off switch (BulwarkDB.areas[key].enabled). Its modules (NS:RegisterModule(name, key)) get
-- OnEnable when the area starts and OnDisable when it stops. An area won't start while the standalone addon it
-- replaces is still loaded (no doubled alerts or marking keys during the switch).

NS.areas = {}               -- ordered list of area specs
NS.areaByKey = {}
local running = {}          -- [key] = true while the area's modules are enabled
local loggedIn = false

--[[ spec fields:
    key, order, title, desc (one line for the Settings > Areas page), icon (file in Media\),
    legacy    = name of the standalone addon this area replaces (optional),
    switch    = false for the Settings tab (always on, no switch),
    pages     = list of { key, title, build = function(page, parent) end, refresh = function(page) end },
    command   = function(args) ... end  (handles "/bwk <key> <args>", optional),
    commandHelp = list of help lines (optional)
]]
function NS:RegisterArea(spec)
    spec.pages = spec.pages or {}
    if spec.switch == nil then spec.switch = true end
    table.insert(NS.areas, spec)
    table.sort(NS.areas, function(a, b) return (a.order or 99) < (b.order or 99) end)
    NS.areaByKey[spec.key] = spec
    if spec.switch then
        NS.DefaultConfig.areas[spec.key] = { enabled = true }
    end
    return spec
end

-- page.before = key of an existing page to insert in front of (e.g. keep "options" last); default: append.
function NS:AddPage(areaKey, page)
    local area = NS.areaByKey[areaKey]
    for i, p in ipairs(area.pages) do
        if page.before and p.key == page.before then
            table.insert(area.pages, i, page)
            return page
        end
    end
    table.insert(area.pages, page)
    return page
end

function NS:GetArea(key)
    return NS.areaByKey[key]
end

function NS:IsAreaEnabled(key)
    local area = NS.areaByKey[key]
    if not area then return false end
    if not area.switch then return true end
    local saved = NS.db and NS.db.areas[key]
    return saved ~= nil and saved.enabled == true
end

function NS:IsAreaRunning(key)
    return running[key] == true
end

-- Name of the standalone addon that keeps this area from starting, or nil.
function NS:AreaBlockedBy(key)
    local area = NS.areaByKey[key]
    if not (area and area.legacy) then return nil end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(area.legacy) then
        return area.legacy
    end
    return nil
end

local function Start(key)
    if running[key] or not loggedIn then return end
    if NS:AreaBlockedBy(key) then return end
    running[key] = true
    NS:CallModules("OnEnable", key)
end

local function Stop(key)
    if not running[key] then return end
    running[key] = nil
    NS:CallModules("OnDisable", key)
end

-- Login: start every enabled area; say once which ones wait for an old addon to be turned off.
function NS:StartAreas()
    loggedIn = true
    for _, area in ipairs(NS.areas) do
        if area.switch and NS:IsAreaEnabled(area.key) then
            local blocker = NS:AreaBlockedBy(area.key)
            if blocker then
                NS:Print(NS.L["AREA_BLOCKED_LOGIN"], area.title, blocker)
            else
                Start(area.key)
            end
        end
    end
end

-- Turns an area on or off. Refused in combat (areas own secure frames). Returns true when the switch moved.
function NS:SetAreaEnabled(key, enabled)
    local area = NS.areaByKey[key]
    if not (area and area.switch) then return false end
    if InCombatLockdown() then
        NS:Print(NS.L["AREA_COMBAT"])
        return false
    end
    NS.db.areas[key].enabled = enabled and true or false
    if enabled then Start(key) else Stop(key) end
    NS:Fire("AREA_CHANGED", key)
    return true
end

-- Status of an area for the UI: "on", "off" or "blocked".
function NS:AreaStatus(key)
    if not NS:IsAreaEnabled(key) then return "off" end
    if NS:AreaBlockedBy(key) then return "blocked" end
    return "on"
end
