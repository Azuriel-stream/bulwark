local ADDON_NAME, NS = ...
local L, Kit = NS.L, NS.Kit

-- Audit: pre-pull buff/consumable/debuff tiles, buff requests and thanks (from TankAuditForever, build step 3).
local area = NS:RegisterArea({
    key = "audit",
    order = 2,
    title = L["AREA_AUDIT"],
    desc = L["AREA_AUDIT_DESC"],
    icon = "tab_audit",
    legacy = "TankAuditForever",
})

local FROM = "TankAuditForever"
for _, def in ipairs({
    { "checks", L["PAGE_CHECKS"] },
    { "blessings", L["PAGE_BLESSINGS"] },
    { "tiles", L["PAGE_TILES"] },
    { "sound", L["PAGE_SOUND"] },
    { "tools", L["PAGE_TOOLS"] },
}) do
    NS:AddPage(area.key, {
        key = def[1],
        title = def[2],
        build = function(page, parent) Kit.Placeholder(parent, page.title, FROM) end,
    })
end
