local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Planned-icon preview: our own frames anchored above Blizzard nameplates (works in dungeons, run 3).
-- Display only; the real mark comes from the pack key. Plates that already show an icon drop out of the plan.
local Overlay = MK:RegisterModule("Overlay")
local Utils = MK.Utils

local pool = {}

local function Acquire(k)
    local f = pool[k]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(22, 22)
        f:SetFrameStrata("LOW")
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f.tex:SetTexture(Utils.ICON_TEXTURE)
        f:SetAlpha(0.55)
        pool[k] = f
    end
    return f
end

function Overlay:HideAll()
    for _, f in pairs(pool) do
        f:Hide()
        f.token = nil
    end
end

function Overlay:Show(plan)
    Overlay:HideAll()
    if not MK.isEnabled or not MK:Get("overlay") then return end
    for k, e in ipairs(plan.entries) do
        local plate = C_NamePlate.GetNamePlateForUnit(e.rec.token)
        if plate then
            local f = Acquire(k)
            f.tex:SetTexCoord(Utils.IconTexCoord(e.icon))
            f:ClearAllPoints()
            if pcall(f.SetPoint, f, "BOTTOM", plate, "TOP", 0, 2) then
                f.token = e.rec.token
                f:Show()
            end
        end
    end
end

local frame = CreateFrame("Frame", "BWK_OverlayFrame")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- Plate frames are recycled for other mobs: never leave an icon on a reused plate.
        for _, f in pairs(pool) do
            if f.token == unit then
                f:Hide()
                f.token = nil
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Overlay:HideAll()   -- the pull has started: the real marks matter now
    end
end)

function Overlay:OnInitialize()
    MK:On("PLAN_CHANGED", function(plan) Overlay:Show(plan) end)
end

function Overlay:OnEnable()
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function Overlay:OnDisable()
    frame:UnregisterAllEvents()
    Overlay:HideAll()
end
