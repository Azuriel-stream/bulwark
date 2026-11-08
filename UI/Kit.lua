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
    return cb
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
