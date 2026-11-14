local ADDON_NAME, NS = ...

-- Window kit: Bulwark's own look (dark panels, thin gold lines, gold-trimmed buttons). Built from plain textures
-- and our own Media\*.tga; nothing is taken from other addons. No Blizzard dropdown menus (kb/gotchas.md#menu-crash).
local Kit = {}
NS.Kit = Kit

Kit.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-- Colours {r, g, b, a}. Gold matches the icon rim (#d9aa3c), the banner matches the icon tile.
Kit.C = {
    bg          = { 0.045, 0.050, 0.060, 0.97 },
    panel       = { 0.070, 0.078, 0.090, 1 },
    card        = { 0.095, 0.102, 0.115, 1 },
    cardBorder  = { 1, 1, 1, 0.08 },
    line        = { 1, 1, 1, 0.07 },
    gold        = { 0.85, 0.67, 0.24, 1 },
    goldDim     = { 0.85, 0.67, 0.24, 0.40 },
    goldText    = { 1.00, 0.82, 0.38, 1 },
    text        = { 0.92, 0.92, 0.93, 1 },
    muted       = { 0.58, 0.60, 0.63, 1 },
    disabled    = { 0.40, 0.41, 0.43, 1 },  -- labels of greyed-out options
    bannerTop   = { 0.17, 0.23, 0.29, 1 },
    bannerBot   = { 0.03, 0.035, 0.045, 1 },
    tab         = { 1, 1, 1, 0.00 },
    tabHover    = { 1, 1, 1, 0.05 },
    tabActive   = { 0.85, 0.67, 0.24, 0.12 },
    button      = { 0.12, 0.11, 0.09, 1 },
    buttonHover = { 0.20, 0.17, 0.10, 1 },
    on          = { 0.00, 0.62, 0.36, 1 },
    off         = { 0.22, 0.23, 0.25, 1 },
    warn        = { 1.00, 0.55, 0.20, 1 },
    noticeBg    = { 1.00, 0.55, 0.20, 0.10 },
}
local C = Kit.C

local counter = 0
-- Unique global names for template widgets (some Blizzard templates expect a name).
function Kit.Name(prefix)
    counter = counter + 1
    return "Bulwark_" .. prefix .. counter
end

local function Snap(tex)
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
end

-- Solid colour texture covering the frame.
function Kit.Fill(frame, c, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetAllPoints()
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

-- Two-colour gradient on a texture. VERTICAL: c1 = bottom, c2 = top; HORIZONTAL: c1 = left, c2 = right.
function Kit.Gradient(tex, orientation, c1, c2)
    tex:SetColorTexture(1, 1, 1, 1)
    pcall(tex.SetGradient, tex, orientation,
        CreateColor(c1[1], c1[2], c1[3], c1[4] or 1), CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
end

-- 1 px border made of four textures. Returns the edge list (for Kit.SetBorderColor).
function Kit.Border(frame, c, layer)
    local edges = {}
    local function Edge(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        Snap(t)
        table.insert(edges, t)
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    return edges
end

function Kit.SetBorderColor(edges, c)
    for _, t in ipairs(edges) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- Horizontal 1 px line across the parent, y pixels below its top.
function Kit.HLine(parent, y, c, inset)
    c, inset = c or C.line, inset or 0
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, y)
    t:SetHeight(1)
    Snap(t)
    return t
end

-- Gold line that fades out at both ends, y pixels below the parent's top.
function Kit.FadeLine(parent, y, c)
    c = c or C.gold
    local clear, solid = { c[1], c[2], c[3], 0 }, { c[1], c[2], c[3], c[4] or 1 }
    local left = parent:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    left:SetPoint("TOPRIGHT", parent, "TOP", 0, y)
    left:SetHeight(1)
    Kit.Gradient(left, "HORIZONTAL", clear, solid)
    local right = parent:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPLEFT", parent, "TOP", 0, y)
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    right:SetHeight(1)
    Kit.Gradient(right, "HORIZONTAL", solid, clear)
    Snap(left); Snap(right)
    return left, right
end

-- Font string in the game's own font file (so other client locales keep their glyphs).
local function FontFile()
    local file = GameFontNormal and GameFontNormal.GetFont and GameFontNormal:GetFont()
    return type(file) == "string" and file or "Fonts\\FRIZQT__.TTF"
end

function Kit.Text(parent, size, c, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FontFile(), size or 12, flags or "")
    c = c or C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    return fs
end

-- Wrapped paragraph of the given width.
function Kit.Paragraph(parent, text, width, size, c)
    local fs = Kit.Text(parent, size or 12, c or C.text)
    fs:SetWidth(width)
    fs:SetJustifyV("TOP")
    fs:SetSpacing(3)
    fs:SetText(text)
    return fs
end

function Kit.SetTextColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Tooltip on hover (title in white, body wrapped).
function Kit.Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Gold-trimmed text button. onClick(button, mouseButton).
function Kit.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 24)
    b.bg = Kit.Fill(b, C.button)
    b.edges = Kit.Border(b, C.goldDim)
    b.label = Kit.Text(b, 12, C.goldText)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self.bg:SetColorTexture(unpack(C.buttonHover))
        Kit.SetBorderColor(self.edges, C.gold)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(unpack(C.button))
        Kit.SetBorderColor(self.edges, C.goldDim)
    end)
    b:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.label:SetPoint("CENTER", 1, -1) end
    end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER") end)
    b:SetScript("OnClick", function(self, button)
        if onClick then onClick(self, button) end
    end)
    function b:SetActive(enabled)
        self:SetEnabled(enabled)
        Kit.SetTextColor(self.label, enabled and C.goldText or C.muted)
    end
    function b:SetLabel(text)
        self.label:SetText(text)
    end
    function b:GetLabel()
        return self.label:GetText()
    end
    return b
end

-- On/off pill. onToggle(switch, wanted) decides and calls switch:SetOn() itself.
function Kit.Switch(parent, onToggle)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(46, 20)
    s.track = Kit.Fill(s, C.off, "ARTWORK")
    s.edges = Kit.Border(s, C.goldDim)
    s.knob = s:CreateTexture(nil, "OVERLAY")
    s.knob:SetSize(18, 16)
    s.knob:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
    s.state = Kit.Text(s, 9, C.text, "OUTLINE")
    function s:SetOn(on)
        self.on = on and true or false
        local c = self.on and C.on or C.off
        self.track:SetColorTexture(c[1], c[2], c[3], c[4])
        self.knob:ClearAllPoints()
        self.state:ClearAllPoints()
        if self.on then
            self.knob:SetPoint("RIGHT", -2, 0)
            self.state:SetPoint("LEFT", 6, 0)
        else
            self.knob:SetPoint("LEFT", 2, 0)
            self.state:SetPoint("RIGHT", -6, 0)
        end
        self.state:SetText(self.on and NS.L["ON"] or NS.L["OFF"])
    end
    s:SetScript("OnEnter", function(self) Kit.SetBorderColor(self.edges, C.gold) end)
    s:SetScript("OnLeave", function(self) Kit.SetBorderColor(self.edges, C.goldDim) end)
    s:SetScript("OnClick", function(self)
        if onToggle then onToggle(self, not self.on) end
    end)
    s:SetOn(false)
    return s
end

-- Checkbox (UICheckButtonTemplate, [in-game] proven in TAF). onClick(checked).
function Kit.Checkbox(parent, text, tooltip, onClick)
    local cb = CreateFrame("CheckButton", Kit.Name("Check"), parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.Text:SetFontObject("GameFontHighlight")
    cb.Text:SetText(text)
    cb:SetScript("OnClick", function(self)
        if onClick then onClick(self:GetChecked() and true or false) end
    end)
    if tooltip then Kit.Tooltip(cb, text, tooltip) end
    -- Greyed out when an option it depends on is off: the box can't be clicked and the label dims. The value stays.
    local r, g, b, a = cb.Text:GetTextColor()
    function cb:SetActive(enabled)
        self:SetEnabled(enabled)
        if enabled then self.Text:SetTextColor(r, g, b, a) else Kit.SetTextColor(self.Text, C.disabled) end
    end
    return cb
end

---------------------------------------------------------------------------------------------------------------
-- Dropdown: our own list of plain buttons (the idea seen working in OneForAll on the live client). Blizzard's
-- menu system (WowStyle1DropdownTemplate / Blizzard_Menu) is still not used: it crashed the beta client
-- (kb/gotchas.md#menu-crash). One list at a time; a click outside, a page change or closing the window closes it.
-- options = { { key =, label = [, icon =, iconCoords = {l, r, t, b}][, color = {r, g, b}][, header = true] }, ... }
---------------------------------------------------------------------------------------------------------------

local LIST_ROW_H, LIST_MAX_ROWS = 20, 14
local list, catcher

-- Small down chevron from two rotated lines (our own art).
local function Chevron(parent, c)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(10, 6)
    for i, angle in ipairs({ -math.pi / 4, math.pi / 4 }) do
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetSize(7, 1.5)
        t:SetPoint("CENTER", holder, "CENTER", i == 1 and -2 or 2, 0)
        t:SetRotation(angle)
        Snap(t)
    end
    return holder
end

local function ListRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(LIST_ROW_H)
    r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * LIST_ROW_H)
    r:SetPoint("RIGHT", list, "RIGHT", -10, 0)
    r.hi = Kit.Fill(r, C.tabActive, "HIGHLIGHT")
    r.check = Kit.Fill(r, C.gold, "ARTWORK")
    r.check:ClearAllPoints()
    r.check:SetPoint("LEFT", 2, 0)
    r.check:SetSize(3, LIST_ROW_H - 6)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 10, 0)
    r.text = Kit.Text(r, 12)
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        local o, onPick = self.option, list.onPick
        Kit.CloseList()
        if o and onPick then onPick(o.key, o) end
    end)
    return r
end

local function DrawList()
    local options, w = list.options, list.width
    local visible = math.min(#options, LIST_MAX_ROWS)
    list.offset = math.max(0, math.min(list.offset, #options - visible))
    for i = 1, LIST_MAX_ROWS do
        local r = list.rows[i] or ListRow(i)
        list.rows[i] = r
        local o = options[list.offset + i]
        r.option = o
        r:SetShown(i <= visible and o ~= nil)
        if o then
            r:SetEnabled(not o.header)
            r.icon:SetShown(o.icon ~= nil)
            if o.icon then
                r.icon:SetTexture(o.icon)
                if o.iconCoords then r.icon:SetTexCoord(unpack(o.iconCoords)) else r.icon:SetTexCoord(0, 1, 0, 1) end
            end
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", o.header and 6 or (o.icon and 30 or 10), 0)
            r.text:SetPoint("RIGHT", -4, 0)
            r.text:SetText(o.label)
            local selected = not o.header and o.key == list.current
            r.check:SetShown(selected)
            Kit.SetTextColor(r.text, o.header and C.muted or (selected and C.goldText) or o.color or C.text)
        end
    end
    -- Scroll thumb when the list is longer than the window
    local scrolling = #options > visible
    list.track:SetShown(scrolling)
    if scrolling then
        local trackH = visible * LIST_ROW_H
        local thumbH = math.max(12, trackH * visible / #options)
        list.thumb:SetHeight(thumbH)
        list.thumb:SetPoint("TOP", list.track, "TOP", 0, -(trackH - thumbH) * list.offset / (#options - visible))
    end
    list:SetSize(w, visible * LIST_ROW_H + 8)
end

local function BuildList()
    catcher = CreateFrame("Button", "Bulwark_DropdownCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() Kit.CloseList() end)
    catcher:Hide()
    list = CreateFrame("Frame", "Bulwark_DropdownList", UIParent)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(20)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    Kit.Fill(list, C.panel)
    Kit.Border(list, C.goldDim)
    list.track = CreateFrame("Frame", nil, list)
    list.track:SetPoint("TOPRIGHT", -3, -4)
    list.track:SetPoint("BOTTOMRIGHT", -3, 4)
    list.track:SetWidth(3)
    Kit.Fill(list.track, C.line)
    list.thumb = Kit.Fill(list.track, C.goldDim, "ARTWORK")
    list.thumb:ClearAllPoints()
    list.thumb:SetWidth(3)
    list.rows = {}
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = list.offset - delta * 3
        DrawList()
    end)
    list:SetScript("OnHide", function() catcher:Hide() end)
    list:Hide()
end

-- Open the shared list under owner. current = the key shown as selected; onPick(key, option).
function Kit.OpenList(owner, options, current, onPick, width)
    if not list then BuildList() end
    if list:IsShown() and list.owner == owner then Kit.CloseList() return end
    list.owner, list.options, list.current, list.onPick = owner, options, current, onPick
    list.width = math.max(width or 0, owner:GetWidth() or 160)
    -- Same scale as the window the owner sits in (the list hangs off UIParent so it isn't clipped)
    list:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    -- Open scrolled to the selected entry
    list.offset = 0
    for i, o in ipairs(options) do
        if o.key == current and not o.header then list.offset = i - math.floor(LIST_MAX_ROWS / 2) end
    end
    DrawList()
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    catcher:Show()
    list:Show()
end

function Kit.CloseList()
    if list and list:IsShown() then list:Hide() end
end

function Kit.IsListOpen(owner)
    return list ~= nil and list:IsShown() and (owner == nil or list.owner == owner)
end

-- Changing page or closing the window closes an open list.
NS:On("WINDOW_CHANGED", function() Kit.CloseList() end)

-- Button that shows the current choice and opens the list. getOptions() -> options; getCurrent() -> key;
-- onPick(key, option). dd:Refresh() redraws the label (call it from the page's refresh).
function Kit.Dropdown(parent, width, getOptions, getCurrent, onPick, listWidth)
    local dd = Kit.Button(parent, "", width, nil)
    dd.label:ClearAllPoints()
    dd.label:SetPoint("LEFT", 10, 0)
    dd.label:SetPoint("RIGHT", -24, 0)
    dd.label:SetWordWrap(false)
    dd.arrow = Chevron(dd, C.goldText)
    dd.arrow:SetPoint("RIGHT", -9, 0)
    dd.icon = dd:CreateTexture(nil, "OVERLAY")
    dd.icon:SetSize(16, 16)
    dd.icon:SetPoint("LEFT", 8, 0)
    dd.icon:Hide()
    dd:SetScript("OnMouseDown", nil)
    dd:SetScript("OnMouseUp", nil)
    dd:SetScript("OnClick", function(self)
        Kit.OpenList(self, getOptions(), getCurrent(), function(key, o)
            if onPick then onPick(key, o) end
            self:Refresh()
        end, listWidth)
    end)
    function dd:Refresh()
        local current, shown = getCurrent(), nil
        for _, o in ipairs(getOptions()) do
            if o.key == current and not o.header then shown = o break end
        end
        self.label:SetText(shown and shown.label or "-")
        self.icon:SetShown(shown ~= nil and shown.icon ~= nil)
        if shown and shown.icon then
            self.icon:SetTexture(shown.icon)
            if shown.iconCoords then self.icon:SetTexCoord(unpack(shown.iconCoords)) else self.icon:SetTexCoord(0, 1, 0, 1) end
        end
        self.label:SetPoint("LEFT", (shown and shown.icon) and 30 or 10, 0)
    end
    local setActive = dd.SetActive
    function dd:SetActive(enabled)
        setActive(self, enabled)
        dd.arrow:SetAlpha(enabled and 1 or 0.4)
    end
    return dd
end

-- Slider with < > steppers (MinimalSliderWithSteppersTemplate, [in-game] proven in TAF).
-- format(value) -> text for the value label; onChange(value) after rounding to step.
-- deferred: while the thumb is dragged only the label follows; onChange runs once on release. Needed when the
-- change moves the slider itself (the window-size slider rescales its own window: [in-game] applying every step
-- made the slider run away under the cursor to the maximum).
function Kit.Slider(parent, text, minVal, maxVal, step, format, onChange, deferred)
    local slider = CreateFrame("Frame", Kit.Name("Slider"), parent, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(240, 24)
    local title = Kit.Text(slider, 12, C.goldText)
    title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 19, 3)
    title:SetText(text)
    local Label = MinimalSliderWithSteppersMixin.Label
    local formatters = {
        [Label.Right] = CreateMinimalSliderFormatter(Label.Right, function(value)
            return format and format(value) or tostring(value)
        end),
    }
    step = step or 1
    slider:Init(minVal, minVal, maxVal, math.floor((maxVal - minVal) / step + 0.5), formatters)
    local dragging, pending = false, nil
    local function Apply(value)
        if onChange then onChange(math.floor(value / step + 0.5) * step) end
    end
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if deferred and dragging then pending = value else Apply(value) end
    end, slider)
    if deferred then
        slider.Slider:HookScript("OnMouseDown", function() dragging = true end)
        slider.Slider:HookScript("OnMouseUp", function()
            dragging = false
            if pending then
                local value = pending
                pending = nil
                Apply(value)
            end
        end)
    end
    return slider
end

-- Section card with an optional gold title and a hairline under it. Content starts 38 px below the top.
function Kit.Card(parent, title)
    local card = CreateFrame("Frame", nil, parent)
    Kit.Fill(card, C.card)
    Kit.Border(card, C.cardBorder)
    if title then
        card.title = Kit.Text(card, 13, C.goldText)
        card.title:SetPoint("TOPLEFT", 14, -12)
        card.title:SetText(title)
        Kit.HLine(card, -30, C.line, 14)
    end
    return card
end

-- Page heading + one-line description at the top of a page. Returns the y offset where content can start.
function Kit.PageHeader(parent, title, desc)
    local h = Kit.Text(parent, 18, C.goldText)
    h:SetPoint("TOPLEFT", 0, 0)
    h:SetText(title)
    local y = -28
    if desc then
        local d = Kit.Paragraph(parent, desc, 600, 12, C.muted)
        d:SetPoint("TOPLEFT", 0, y)
        y = y - 30
    end
    return y
end

-- Stand-in page for features that move into Bulwark in a later build step.
function Kit.Placeholder(parent, title, from)
    local y = Kit.PageHeader(parent, title)
    local card = Kit.Card(parent)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card:SetHeight(64)
    local text = Kit.Paragraph(card, string.format(NS.L["PLACEHOLDER"], from), 560, 12, C.muted)
    text:SetPoint("TOPLEFT", 16, -16)
    return card
end
