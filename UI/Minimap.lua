local ADDON_NAME, NS = ...
local L, Kit = NS.L, NS.Kit

-- Minimap button: drag along the minimap edge, left-click toggles the window, right-click opens Settings.
-- Follows a square minimap when another addon reports one through the usual GetMinimapShape() global
-- (OneForAll can square the minimap).
local Mini = NS:RegisterModule("MinimapButton")
local button

local atan2 = math.atan2

local function Shape()
    local fn = rawget(_G, "GetMinimapShape")   -- defined by minimap addons, not by Blizzard
    if type(fn) == "function" then
        local ok, shape = pcall(fn)
        if ok and type(shape) == "string" then return shape end
    end
    return "ROUND"
end

local function Place()
    local angle = math.rad(NS.db.minimap.angle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (Minimap:GetWidth() or 140) / 2
    local h = (Minimap:GetHeight() or 140) / 2
    if Shape() == "SQUARE" then
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m * (w + 4), y / m * (h + 4)
    else
        x, y = x * (w + 10), y * (h + 10)
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function ShowTooltip(self)
    if self.dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["TITLE"], 1, 0.82, 0.38)
    GameTooltip:AddLine(L["MINIMAP_TIP_LEFT"], 1, 1, 1)
    GameTooltip:AddLine(L["MINIMAP_TIP_RIGHT"], 1, 1, 1)
    GameTooltip:AddLine(L["MINIMAP_TIP_DRAG"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function OnClick(_, mouseButton)
    if mouseButton == "RightButton" then
        NS.Window:Open("settings")
    else
        NS.Window:Toggle()
    end
end

local function Create()
    button = CreateFrame("Button", "Bulwark_MinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(Kit.MEDIA .. "minimap")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            if not (mx and my and scale and cx and cy) then return end
            NS.db.minimap.angle = math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360
            Place()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragging = false
    end)
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", Place) end
    Place()
end

-- Settings > Window checkbox and /bwk minimap.
function Mini:SetEnabled(show)
    NS.db.minimap.hide = not show
    if show and not button and Minimap then Create() end
    if button then button:SetShown(show) end
end

function Mini:IsEnabled()
    return not NS.db.minimap.hide
end

function Mini:GetButton()
    return button
end

function Mini:OnEnable()
    if not Minimap then return end
    if not NS.db.minimap.hide then Create() end
end

-- Blizzard's addon compartment (TOC ## AddonCompartmentFunc), if this client lists addons there [unverified].
_G["Bulwark_OnCompartmentClick"] = function(_, mouseButton)
    OnClick(nil, mouseButton)
end
