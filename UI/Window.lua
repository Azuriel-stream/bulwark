local ADDON_NAME, NS = ...
local L, Kit = NS.L, NS.Kit
local C = Kit.C

-- Main window: banner, tab bar (one tab per area, Settings on the right), side menu with the area's pages, page.
-- Built on first open; each page is built the first time it's shown. Plain (non-secure) frames only, so it can
-- open, switch tabs and close in combat.
local Window = NS:RegisterModule("Window")

local W, H = 900, 600
local BANNER_H, TABBAR_H, NAV_W, PAD = 70, 34, 196, 20
local TAB_W, SETTINGS_TAB_W = 136, 124
local MIN_SCALE, MAX_SCALE = 0.6, 1.4
Window.MIN_SCALE, Window.MAX_SCALE = MIN_SCALE, MAX_SCALE

local frame, pageHost, notice
local tabs = {}         -- [areaKey] = tab button
local navs = {}         -- [areaKey] = side-menu frame
local activeArea, activePage
Window.tabs, Window.navs = tabs, navs   -- for tests

local function db() return NS.db.ui end

---------------------------------------------------------------------------------------------------------------
-- Position and scale
---------------------------------------------------------------------------------------------------------------

local function ApplyPosition()
    frame:ClearAllPoints()
    local ui = db()
    if ui.x and ui.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ui.x, ui.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function SavePosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        db().x, db().y = left, top
    end
    ApplyPosition()
end

local function ClampScale(s)
    s = tonumber(s) or 1
    if s < MIN_SCALE then s = MIN_SCALE elseif s > MAX_SCALE then s = MAX_SCALE end
    return math.floor(s * 100 + 0.5) / 100
end

-- New scale; keeps the window's top-left corner where it is on screen.
function Window:SetScale(scale)
    scale = ClampScale(scale)
    local ui = db()
    if frame and ui.x and ui.y then
        local old = frame:GetScale() or ui.scale
        ui.x, ui.y = ui.x * old / scale, ui.y * old / scale
    end
    ui.scale = scale
    if frame then
        frame:SetScale(scale)
        ApplyPosition()
    end
end

function Window:ResetPosition()
    db().x, db().y = nil, nil
    if frame then ApplyPosition() end
end

---------------------------------------------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------------------------------------------

local function PaintTab(tab)
    local active = tab.area.key == activeArea
    local c = active and C.tabActive or (tab.hover and C.tabHover or C.tab)
    tab.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    tab.bar:SetShown(active)
    local status = NS:AreaStatus(tab.area.key)
    local live = (status == "on") or not tab.area.switch
    tab.icon:SetDesaturated(not live)
    tab.icon:SetAlpha(live and 1 or 0.6)
    Kit.SetTextColor(tab.label, active and C.goldText or (live and C.text or C.muted))
end

local function CreateTab(parent, area, width)
    local tab = CreateFrame("Button", nil, parent)
    tab.area = area
    tab:SetSize(width, TABBAR_H)
    tab.bg = Kit.Fill(tab, C.tab)
    tab.bar = tab:CreateTexture(nil, "OVERLAY")
    tab.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    tab.bar:SetPoint("BOTTOMLEFT", 6, 0)
    tab.bar:SetPoint("BOTTOMRIGHT", -6, 0)
    tab.bar:SetHeight(2)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(22, 22)
    tab.icon:SetPoint("LEFT", 12, 0)
    tab.icon:SetTexture(Kit.MEDIA .. area.icon)
    tab.label = Kit.Text(tab, 13)
    tab.label:SetPoint("LEFT", tab.icon, "RIGHT", 8, 0)
    tab.label:SetText(area.title)
    tab:SetScript("OnEnter", function(self) self.hover = true; PaintTab(self) end)
    tab:SetScript("OnLeave", function(self) self.hover = false; PaintTab(self) end)
    tab:SetScript("OnClick", function(self) Window:Select(self.area.key) end)
    return tab
end

---------------------------------------------------------------------------------------------------------------
-- Side menu (per area): title, on/off switch, status, page entries
---------------------------------------------------------------------------------------------------------------

local function PaintEntry(entry)
    local selected = entry.nav.selected == entry.page.key
    entry.marker:SetShown(selected)
    local c = selected and C.tabActive or (entry.hover and C.tabHover or C.tab)
    entry.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    Kit.SetTextColor(entry.label, selected and C.goldText or C.text)
end

local function StatusText(area)
    local status = NS:AreaStatus(area.key)
    if status == "on" then return "|cff00c070" .. L["STATUS_ON"] .. "|r" end
    if status == "blocked" then return "|cffff8c33" .. L["STATUS_WAITING"] .. "|r" end
    return "|cff8a8d91" .. L["STATUS_OFF"] .. "|r"
end

local function CreateNav(parent, area)
    local nav = CreateFrame("Frame", nil, parent)
    nav:SetAllPoints()
    nav.area = area
    nav.entries = {}

    local title = Kit.Text(nav, 16, C.goldText)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(area.title)

    local y = -44
    if area.switch then
        nav.switch = Kit.Switch(nav, function(_, wanted)
            NS:SetAreaEnabled(area.key, wanted)
            Window:Refresh()
        end)
        nav.switch:SetPoint("TOPRIGHT", -14, -15)
        Kit.Tooltip(nav.switch, string.format(L["SWITCH_TIP_TITLE"], area.title), L["SWITCH_TIP"])
        nav.status = Kit.Text(nav, 11, C.muted)
        nav.status:SetPoint("TOPLEFT", 16, -38)
        y = -60
    end
    Kit.HLine(nav, y, C.line, 12)
    y = y - 10

    for _, page in ipairs(area.pages) do
        local entry = CreateFrame("Button", nil, nav)
        entry.nav, entry.page = nav, page
        entry:SetPoint("TOPLEFT", 8, y)
        entry:SetPoint("TOPRIGHT", -8, y)
        entry:SetHeight(28)
        entry.bg = Kit.Fill(entry, C.tab)
        entry.marker = entry:CreateTexture(nil, "OVERLAY")
        entry.marker:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        entry.marker:SetPoint("TOPLEFT")
        entry.marker:SetPoint("BOTTOMLEFT")
        entry.marker:SetWidth(3)
        entry.label = Kit.Text(entry, 13)
        entry.label:SetPoint("LEFT", 16, 0)
        entry.label:SetText(page.title)
        entry:SetScript("OnEnter", function(self) self.hover = true; PaintEntry(self) end)
        entry:SetScript("OnLeave", function(self) self.hover = false; PaintEntry(self) end)
        entry:SetScript("OnClick", function(self) Window:Select(area.key, self.page.key) end)
        table.insert(nav.entries, entry)
        y = y - 30
    end
    nav:Hide()
    return nav
end

---------------------------------------------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------------------------------------------

local function FindPage(area, key)
    for _, page in ipairs(area.pages) do
        if page.key == key then return page end
    end
    return area.pages[1]
end

local function ShowPage(area, page)
    for _, other in ipairs(NS.areas) do
        for _, p in ipairs(other.pages) do
            if p.frame and p ~= page then p.frame:Hide() end
        end
    end
    if not page then return end
    if not page.frame then
        page.frame = CreateFrame("Frame", nil, pageHost)
        page.frame:SetAllPoints()
        local ok, err = xpcall(page.build, NS.Trap, page, page.frame)
        if not ok then NS:Print("|cffFF4444Error building page %s:|r %s", page.key, tostring(err)) end
    end
    page.frame:Show()
    if page.refresh then
        local ok, err = xpcall(page.refresh, NS.Trap, page)
        if not ok then NS:Print("|cffFF4444Error refreshing page %s:|r %s", page.key, tostring(err)) end
    end
end

-- Notice strip above the page while the area is off or waits for an old addon.
local function UpdateNotice(area)
    local status = area.switch and NS:AreaStatus(area.key) or "on"
    pageHost:ClearAllPoints()
    if status == "on" then
        notice:Hide()
        pageHost:SetPoint("TOPLEFT", notice:GetParent(), "TOPLEFT", PAD, -PAD)
    else
        if status == "blocked" then
            notice.text:SetText(string.format(L["NOTICE_BLOCKED"], area.title, NS:AreaBlockedBy(area.key) or "?"))
        else
            notice.text:SetText(string.format(L["NOTICE_OFF"], area.title))
        end
        notice:Show()
        pageHost:SetPoint("TOPLEFT", notice, "BOTTOMLEFT", 0, -PAD)
    end
    pageHost:SetPoint("BOTTOMRIGHT", notice:GetParent(), "BOTTOMRIGHT", -PAD, PAD)
end

---------------------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------------------

local function Create()
    frame = CreateFrame("Frame", "BulwarkWindow", UIParent)
    frame:Hide()
    frame:SetSize(W, H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetDontSavePosition(true)
    frame:SetScale(ClampScale(db().scale))
    ApplyPosition()
    Kit.Fill(frame, C.bg)
    Kit.Border(frame, C.goldDim, "OVERLAY")
    table.insert(UISpecialFrames, "BulwarkWindow")  -- Esc closes it

    -- Banner: drag handle, logo, name, tagline, version, close button.
    local banner = CreateFrame("Frame", nil, frame)
    banner:SetPoint("TOPLEFT", 1, -1)
    banner:SetPoint("TOPRIGHT", -1, -1)
    banner:SetHeight(BANNER_H)
    Kit.Gradient(Kit.Fill(banner, C.bannerBot), "VERTICAL", C.bannerBot, C.bannerTop)
    banner:EnableMouse(true)
    banner:RegisterForDrag("LeftButton")
    banner:SetScript("OnDragStart", function() frame:StartMoving() end)
    banner:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)

    local logo = banner:CreateTexture(nil, "ARTWORK")
    logo:SetSize(52, 52)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture(Kit.MEDIA .. "icon")

    local name = Kit.Text(banner, 28, C.goldText)
    name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -4)
    name:SetText(L["TITLE_BANNER"])
    local tagline = Kit.Text(banner, 12, C.muted)
    tagline:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 2, -4)
    tagline:SetText(L["TAGLINE"])

    local close = CreateFrame("Button", nil, banner, "UIPanelCloseButtonNoScripts")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() frame:Hide() end)  -- plain Hide works in combat (kb/gotchas.md#close-in-combat)

    local version = Kit.Text(banner, 11, C.muted)
    version:SetPoint("BOTTOMRIGHT", -14, 10)
    version:SetText("v" .. NS.version)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, 0)
    tabBar:SetHeight(TABBAR_H)
    Kit.Fill(tabBar, C.panel)
    Kit.FadeLine(tabBar, 0, C.gold)
    Kit.HLine(tabBar, -TABBAR_H + 1, C.line)
    local x, xRight = 8, -8
    for _, area in ipairs(NS.areas) do
        if area.switch then
            local tab = CreateTab(tabBar, area, TAB_W)
            tab:SetPoint("BOTTOMLEFT", x, 0)
            x = x + TAB_W + 2
            tabs[area.key] = tab
        else
            local tab = CreateTab(tabBar, area, SETTINGS_TAB_W)
            tab:SetPoint("BOTTOMRIGHT", xRight, 0)
            xRight = xRight - SETTINGS_TAB_W - 2
            tabs[area.key] = tab
        end
    end

    -- Body: side menu + page area
    local navPanel = CreateFrame("Frame", nil, frame)
    navPanel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    navPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    navPanel:SetWidth(NAV_W)
    Kit.Fill(navPanel, C.panel)
    local navEdge = navPanel:CreateTexture(nil, "ARTWORK")
    navEdge:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    navEdge:SetPoint("TOPRIGHT")
    navEdge:SetPoint("BOTTOMRIGHT")
    navEdge:SetWidth(1)
    for _, area in ipairs(NS.areas) do
        navs[area.key] = CreateNav(navPanel, area)
    end

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", navPanel, "TOPRIGHT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

    notice = CreateFrame("Frame", nil, body)
    notice:SetPoint("TOPLEFT", PAD, -PAD)
    notice:SetPoint("TOPRIGHT", -PAD, -PAD)
    notice:SetHeight(36)
    Kit.Fill(notice, C.noticeBg)
    Kit.Border(notice, { C.warn[1], C.warn[2], C.warn[3], 0.5 })
    notice.text = Kit.Text(notice, 12, C.warn)
    notice.text:SetPoint("LEFT", 12, 0)
    notice.text:SetPoint("RIGHT", -12, 0)
    notice:Hide()

    pageHost = CreateFrame("Frame", nil, body)

    frame:SetScript("OnShow", function()
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        Window:Refresh()
        NS:Fire("WINDOW_CHANGED", true, activeArea, activePage)
    end)
    frame:SetScript("OnHide", function()
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
        NS:Fire("WINDOW_CHANGED", false, activeArea, activePage)
    end)
end

---------------------------------------------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------------------------------------------

-- Repaints tabs, the active side menu (switch, status) and the notice.
function Window:Refresh()
    if not frame then return end
    for _, tab in pairs(tabs) do PaintTab(tab) end
    local area = NS:GetArea(activeArea)
    if not area then return end
    local nav = navs[area.key]
    if nav.switch then
        nav.switch:SetOn(NS:IsAreaEnabled(area.key))
        nav.status:SetText(StatusText(area))
    end
    for _, entry in ipairs(nav.entries) do PaintEntry(entry) end
    UpdateNotice(area)
end

-- Shows an area's tab and one of its pages (default: the page last shown for that area).
function Window:Select(areaKey, pageKey)
    if not frame then Create() end
    local area = NS:GetArea(areaKey) or NS.areas[1]
    activeArea = area.key
    NS.char.lastTab = area.key
    local page = FindPage(area, pageKey or NS.char.lastPage[area.key])
    activePage = page and page.key
    NS.char.lastPage[area.key] = activePage
    for key, nav in pairs(navs) do nav:SetShown(key == area.key) end
    navs[area.key].selected = activePage
    ShowPage(area, page)
    Window:Refresh()
    -- (shown, areaKey, pageKey): areas react to being looked at (Audit previews its tiles).
    NS:Fire("WINDOW_CHANGED", frame:IsShown(), activeArea, activePage)
end

function Window:Open(areaKey, pageKey)
    if not frame then Create() end
    Window:Select(areaKey or NS.char.lastTab, pageKey)
    frame:Show()
end

function Window:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Window:Open()
    end
end

function Window:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Window:GetFrame()
    return frame
end

function Window:GetActive()
    return activeArea, activePage
end

function Window:OnInitialize()
    NS:On("AREA_CHANGED", function() Window:Refresh() end)
end
