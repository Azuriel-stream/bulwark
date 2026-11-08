local ADDON_NAME, NS = ...
local L, Kit = NS.L, NS.Kit

-- Marking: pre-pull pack planner, one-key marking, team setup and mob database (from TankMarkForever, build step 4).
local area = NS:RegisterArea({
    key = "marking",
    order = 3,
    title = L["AREA_MARKING"],
    desc = L["AREA_MARKING_DESC"],
    icon = "tab_marking",
    legacy = "TankMarkForever",
})

local FROM = "TankMarkForever"
for _, def in ipairs({
    { "team", L["PAGE_TEAM"] },
    { "mobs", L["PAGE_MOBS"] },
    { "options", L["PAGE_OPTIONS"] },
    { "keys", L["PAGE_KEYS"] },
}) do
    NS:AddPage(area.key, {
        key = def[1],
        title = def[2],
        build = function(page, parent) Kit.Placeholder(parent, page.title, FROM) end,
    })
end
