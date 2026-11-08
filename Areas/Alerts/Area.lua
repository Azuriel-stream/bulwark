local ADDON_NAME, NS = ...
local L, Kit = NS.L, NS.Kit

-- Alerts: combat failure alerts, loss-of-control alerts and threat whispers (from TankAlertForever, build step 2).
local area = NS:RegisterArea({
    key = "alerts",
    order = 1,
    title = L["AREA_ALERTS"],
    desc = L["AREA_ALERTS_DESC"],
    icon = "tab_alerts",
    legacy = "TankAlertForever",
})

local FROM = "TankAlertForever"
for _, def in ipairs({
    { "general", L["PAGE_GENERAL"] },
    { "abilities", L["PAGE_ABILITIES"] },
    { "cc", L["PAGE_CC"] },
    { "threat", L["PAGE_THREAT"] },
    { "channel", L["PAGE_CHANNEL"] },
}) do
    NS:AddPage(area.key, {
        key = def[1],
        title = def[2],
        build = function(page, parent) Kit.Placeholder(parent, page.title, FROM) end,
    })
end
