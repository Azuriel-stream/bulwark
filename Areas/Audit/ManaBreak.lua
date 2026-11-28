local ADDON_NAME, NS = ...
local Utils, L, Voices = NS.Utils, NS.L, NS.AuditVoices

-- Mana break (user 2026-11-28; kb/addons/Bulwark.md "Audit: mana break"). 5-man groups only, out of combat, outside
-- rest areas (with Audit's "Hide while resting"):
--  * YOUR mana is plain: a clickable tile below the threshold ("I need a drink" to the party). It stays until you're
--    back to RESUME % or you pull (combat).
--  * The HEALER's mana is always secret to addons, even out of combat [in-game 2026-11-28], so Lua can't compare it.
--    UnitPowerPercent turns it into an alpha through a curve (secret in, secret out) and Frame:SetAlpha takes the
--    secret (AllowedWhenTainted [docs]), so the prompt fades in on its own below the threshold; its text shows the %
--    the same way (SetFormattedText). The mouse can't follow a secret (EnableMouse / SetHitRectInsets: NotAllowed),
--    so the prompt never takes clicks: the key (BWK_ManaBreakButton) or /bwk audit mana announces.
--    Drinking is a plain aura read out of combat: the prompt stays fully shown while the healer drinks.
local MB = NS:RegisterModule("AuditManaBreak", "audit")
NS.AuditManaBreak = MB

local SIZE = 32
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local RESUME = 90               -- your own tile stays until you're back to this %
local THROTTLE = 10             -- seconds between announcements
local BINDING = "CLICK BWK_ManaBreakButton:LeftButton"
local DRINK_SPELLS = { 430, 167152 }   -- every drink aura is "Drink" (430 ...), Forever's table "Refreshment" [data]
local HEALER_CLASSES = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
local FALLBACK_ICON = "Interface\\Icons\\INV_Drink_07"

_G["BINDING_NAME_" .. BINDING] = L["MANA_BINDING"]

local frame, selfTile, prompt
local preview = false          -- Edit Mode
local windowPreview = false    -- the Bulwark window shows the Audit tab
local selfLow = false          -- your tile is up (hysteresis: below threshold -> on, RESUME % or combat -> off)
local lastSent = -math.huge
local queued = false
local curves = {}              -- [threshold] = { alpha = curve, pct = curve }

MB.healerUnit, MB.healerName, MB.healerHow = nil, nil, nil

local function cfg() return NS.db.audit end

-- =========================================================================
-- Pure part
-- =========================================================================

function MB.FiveMan() return IsInGroup() and not IsInRaid() end

local function Role(unit)
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    return ok and Utils.SafeString(role, nil) or nil
end

local function ClassOf(unit)
    local ok, _, class = pcall(UnitClass, unit)
    return ok and Utils.SafeString(class, nil) or nil
end

-- The healer of a 5-man group: unit, first name, how ("pick" on the page, group "role", the only healing "class").
function MB.FindHealer()
    if not MB.FiveMan() then return nil end
    local pick = cfg().manaHealerPick
    if pick == "" then pick = nil end
    local byRole, byClass, classCount = nil, nil, 0
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party" .. i
        if UnitExists(unit) then
            if pick and Voices.FirstName(unit) == pick then return unit, pick, "pick" end
            if not byRole and Role(unit) == "HEALER" then byRole = unit end
            if HEALER_CLASSES[ClassOf(unit) or ""] then
                byClass = unit
                classCount = classCount + 1
            end
        end
    end
    if byRole then return byRole, Voices.FirstName(byRole), "role" end
    if classCount == 1 then return byClass, Voices.FirstName(byClass), "class" end
    return nil
end

-- Your own mana in % (plain), or nil when you have none (Warriors) or it can't be read.
function MB.SelfPercent()
    local okC, cur = pcall(UnitPower, "player", MANA)
    local okM, max = pcall(UnitPowerMax, "player", MANA)
    cur = okC and Utils.SafeNumber(cur, nil)
    max = okM and Utils.SafeNumber(max, nil)
    if not cur or not max or max <= 0 then return nil end
    return cur / max * 100
end

local drinkNames
local function DrinkNames()
    if drinkNames then return drinkNames end
    local names = {}
    for _, id in ipairs(DRINK_SPELLS) do
        local ok, name = pcall(C_Spell.GetSpellName, id)
        name = ok and Utils.SafeString(name, nil)
        if name then names[name] = true end
    end
    if not next(names) then names = { Drink = true, Refreshment = true } end
    drinkNames = names
    return names
end

-- Is this group member drinking? Aura reads are plain out of combat; in combat this says no.
function MB.IsDrinking(unit)
    if InCombatLockdown() then return false end
    local names, found = DrinkNames(), false
    Utils.ForEachAura(unit, "HELPFUL", function(aura)
        local name = Utils.SafeString(aura.name, nil)
        if name and names[name] then found = true end
    end)
    return found
end

local function Usable(unit)
    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
    local okC, online = pcall(UnitIsConnected, unit)
    if okD and not Utils.IsSecret(dead) and dead then return false end
    if okC and not Utils.IsSecret(online) and not online then return false end
    return true
end

-- Curves for a threshold: alpha 1 below it, 0 from it on (a 0.1 % linear ramp: no Step semantics to guess); and 0..1
-- -> 0..100 for the label.
local function Curves(threshold)
    if curves[threshold] then return curves[threshold] end
    local util = C_CurveUtil
    if not (util and util.CreateCurve) then return nil end
    local t = threshold / 100
    local alpha = util.CreateCurve()
    local pct = util.CreateCurve()
    local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
    if linear then alpha:SetType(linear); pct:SetType(linear) end
    alpha:AddPoint(0, 1)
    alpha:AddPoint(math.max(0, t - 0.001), 1)
    alpha:AddPoint(t, 0)
    alpha:AddPoint(1, 0)
    pct:AddPoint(0, 0)
    pct:AddPoint(1, 100)
    curves[threshold] = { alpha = alpha, pct = pct }
    return curves[threshold]
end

-- A reading we got back: a secret (never compared, not even with nil) or a plain number.
local function Got(v) return Utils.IsSecret(v) or type(v) == "number" end

-- The healer's alpha and mana % (both may be secret: only ever handed to SetAlpha / SetFormattedText).
local function HealerReadings(unit)
    local c = Curves(cfg().manaThreshold or 40)
    if not c then return nil end
    local okA, alpha = pcall(UnitPowerPercent, unit, MANA, false, c.alpha)
    local okP, pct = pcall(UnitPowerPercent, unit, MANA, false, c.pct)
    if not (okA and Got(alpha)) then return nil end
    if not (okP and Got(pct)) then pct = nil end
    return alpha, pct
end

-- Why nothing shows right now (status, tests), or nil.
function MB.Blocker()
    if not NS:IsAreaRunning("audit") then return "off" end
    local c = cfg()
    if not c.manaBreak then return "option" end
    if InCombatLockdown() then return "combat" end
    if not IsInGroup() then return "solo" end
    if IsInRaid() then return "raid" end
    if c.hideResting and IsResting() then return "resting" end
    return nil
end

-- =========================================================================
-- Frames
-- =========================================================================

local function RestorePosition()
    local p = cfg().manaPoint
    frame:ClearAllPoints()
    if p and tonumber(p.x) and tonumber(p.y) then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -SIZE / 2, -150)
    end
end

local function ReadPosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return { x = left, y = top }
end

local function KeyHint()
    local key = GetBindingKey(BINDING)
    return key and string.format(L["MANA_HINT_KEY"], key) or L["MANA_HINT_NOKEY"]
end

local function SelfTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["MANA_TITLE"], 1, 1, 1)
    local pct = MB.SelfPercent()
    if preview or windowPreview or not pct then
        GameTooltip:AddLine(L["MANA_SELF_PREVIEW"], 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(string.format(L["MANA_SELF_NOW"], math.floor(pct + 0.5)), 1, 0.82, 0)
    end
    GameTooltip:AddLine(L["MANA_SELF_CLICK"], 0.6, 0.8, 1, true)
    GameTooltip:Show()
end

local function DrinkIcon()
    local ok, icon = pcall(C_Spell.GetSpellTexture, DRINK_SPELLS[1])
    return (ok and icon) or FALLBACK_ICON
end

local function Create()
    frame = CreateFrame("Frame", "Bulwark_ManaBreak", UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:Hide()

    -- Your tile: a plain button (sending party chat isn't protected).
    local b = CreateFrame("Button", "Bulwark_ManaBreakSelf", frame)
    b:SetSize(SIZE, SIZE)
    b:SetPoint("LEFT", frame, "LEFT", 0, 0)
    b:RegisterForClicks("LeftButtonUp")
    pcall(b.SetPassThroughButtons, b, "RightButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(DrinkIcon())
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -6, 6)
    b.border:SetPoint("BOTTOMRIGHT", 6, -6)
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetVertexColor(0.3, 0.6, 1)
    b:SetScript("OnEnter", SelfTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() MB.Announce("self") end)
    b:Hide()
    selfTile = b

    -- The healer prompt: picture + text only, never the mouse (see the header).
    local p = CreateFrame("Frame", "Bulwark_ManaBreakHealer", frame)
    p:SetSize(SIZE, SIZE)
    p:EnableMouse(false)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(SIZE, SIZE)
    p.icon:SetPoint("LEFT")
    p.icon:SetTexture(DrinkIcon())
    p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    p.icon:SetVertexColor(0.55, 0.75, 1)
    p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.label:SetPoint("LEFT", p.icon, "RIGHT", 8, 0)
    p.label:SetJustifyH("LEFT")
    p:Hide()
    prompt = p

    RestorePosition()
end

local function Layout()
    prompt:ClearAllPoints()
    if selfTile:IsShown() then
        prompt:SetPoint("LEFT", selfTile, "RIGHT", 8, 0)
    else
        prompt:SetPoint("LEFT", frame, "LEFT", 0, 0)
    end
end

-- =========================================================================
-- When to show
-- =========================================================================

function MB:Refresh()
    if not frame then return end
    local c = cfg()
    frame:SetScale(c.scale or 1)
    if preview or windowPreview then
        selfTile:Show()
        prompt:Show()
        prompt:SetAlpha(1)
        prompt.label:SetText(string.format(L["MANA_HEALER_PCT_PLAIN"], L["MANA_SAMPLE_HEALER"], 28))
        Layout()
        frame:Show()
        return
    end

    local why = MB.Blocker()
    if why then
        if why == "combat" then selfLow = false end   -- you pulled: start fresh after the fight
        MB.healerUnit, MB.healerName, MB.healerHow = nil, nil, nil
        frame:Hide()
        return
    end

    -- You
    local pct = c.manaSelf and MB.SelfPercent() or nil
    if not pct then
        selfLow = false
    elseif pct < (c.manaThreshold or 40) then
        selfLow = true
    elseif pct >= RESUME then
        selfLow = false
    end
    selfTile:SetShown(selfLow)
    if selfLow then NS.FieldTests:Saw("mana-self-tile", { pct = math.floor(pct + 0.5) }) end

    -- The healer
    local unit, name, how
    if c.manaHealer then unit, name, how = MB.FindHealer() end
    if unit and not Usable(unit) then unit = nil end
    MB.healerUnit, MB.healerName, MB.healerHow = unit, name, how
    local shownPrompt = false
    if unit then
        if MB.IsDrinking(unit) then
            prompt:SetAlpha(1)
            prompt.label:SetText(string.format(L["MANA_HEALER_DRINKING"], name or "?"))
            shownPrompt = true
            NS.FieldTests:Saw("mana-healer-prompt", { name = name })
        else
            local alpha, hpct = HealerReadings(unit)
            if Got(alpha) then
                prompt:SetAlpha(alpha)   -- secret: never compared, only handed over
                if Got(hpct) then
                    prompt.label:SetFormattedText(L["MANA_HEALER_PCT"], name or "?", hpct)
                else
                    prompt.label:SetText(name or "?")
                end
                shownPrompt = true
            end
        end
    end
    prompt:SetShown(shownPrompt)
    Layout()
    frame:Show()
end

local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        MB:Refresh()
    end)
end
MB.Queue = Queue

-- =========================================================================
-- Announce (tile click, key, /bwk audit mana)
-- =========================================================================

-- kind: "self", "healer", or nil = the key: the healer if Bulwark knows one, else you (if you have mana).
function MB.Announce(kind)
    if preview or windowPreview then return end
    if not MB.FiveMan() then
        NS:Print(L["MANA_NOT_PARTY"])
        return
    end
    local healerName
    if kind ~= "self" then
        local _, name = MB.FindHealer()
        healerName = name
        if not healerName then
            if kind == "healer" or not MB.SelfPercent() then
                NS:Print(L["MANA_NO_HEALER"])
                return
            end
            kind = "self"
        else
            kind = "healer"
        end
    end
    local now = GetTime()
    if now - lastSent < THROTTLE then
        NS:Print(L["MSG_WAIT_THROTTLE"])
        return
    end
    if Utils.ChatRestricted() then
        NS:Print(L["MSG_CHAT_RESTRICTED"])
        return
    end
    lastSent = now
    C_ChatInfo.SendChatMessage(Voices.ManaBreak(kind, healerName), "PARTY")
    NS.FieldTests:Saw("mana-announce", { kind = kind, healer = healerName, raceVoice = NS.db.audit.raceVoice })
end

-- Key binding target: works whether or not anything is shown.
local keyButton = CreateFrame("Button", "BWK_ManaBreakButton", UIParent)
keyButton:RegisterForClicks("AnyDown", "AnyUp")
local lastKey = -math.huge
keyButton:SetScript("OnClick", function()
    local now = GetTime()
    if now - lastKey < 0.5 then return end   -- a key press can deliver both halves of the click: act once
    lastKey = now
    if NS:IsAreaRunning("audit") and cfg().manaBreak then MB.Announce(nil) end
end)

-- /bwk audit mana status
function MB.Status()
    local why = MB.Blocker()
    if why then
        NS:Print(L["MANA_STATUS_HIDDEN"], L["MANA_BLOCK_" .. why])
        return
    end
    local pct = MB.SelfPercent()
    NS:Print(L["MANA_STATUS_SELF"], pct and string.format("%d%%", math.floor(pct + 0.5)) or L["MANA_NO_MANA"],
        selfLow and L["MANA_SHOWN"] or L["MANA_HIDDEN"])
    if MB.healerUnit then
        NS:Print(L["MANA_STATUS_HEALER"], MB.healerName or "?", L["MANA_HOW_" .. (MB.healerHow or "role")],
            MB.IsDrinking(MB.healerUnit) and L["MANA_DRINKING"] or L["MANA_SECRET"])
    else
        NS:Print(L["MANA_STATUS_NO_HEALER"])
    end
    NS:Print(KeyHint())
end

function MB:SetWindowPreview(enabled)
    windowPreview = enabled and true or false
    Queue()
end

function MB:ResetPosition()
    cfg().manaPoint = nil
    if frame then RestorePosition() end
end

-- =========================================================================
-- Events
-- =========================================================================

local events = CreateFrame("Frame", "Bulwark_ManaBreakEvents")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        selfLow = false
        if frame and not preview and not windowPreview then frame:Hide() end
        return
    end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_AURA" or event == "UNIT_HEALTH"
        or event == "UNIT_CONNECTION" then
        if InCombatLockdown() then return end
        if Utils.IsSecret(unit) then return end
        if unit ~= "player" and unit ~= MB.healerUnit and not (unit and unit:find("^party%d")) then return end
    end
    Queue()
end)

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
                 "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_AURA",
                 "UNIT_HEALTH", "UNIT_CONNECTION" }

function MB:OnEnable()
    if not frame then Create() end
    for _, e in ipairs(EVENTS) do events:RegisterEvent(e) end
    Queue()
end

function MB:OnDisable()
    events:UnregisterAllEvents()
    selfLow = false
    MB.healerUnit, MB.healerName, MB.healerHow = nil, nil, nil
    if frame then frame:Hide() end
end

-- Settings changed on the page (threshold, options, healer pick)
function MB:Changed() Queue() end

function MB:GetFrames() return frame, selfTile, prompt end   -- tests
MB.KeyHint = KeyHint
MB.BINDING = BINDING

-- Blizzard's HUD Edit Mode: both parts show a sample so the frame can be placed; moves wait for Blizzard's Save.
NS.EditMode:Register({
    label = L["EDITMODE_MANA"],
    GetFrame = function() return frame end,
    IsAvailable = function() return frame ~= nil and NS:IsAreaRunning("audit") and cfg().manaBreak and frame:IsShown() end,
    Read = function() return ReadPosition() end,
    Save = function(pos) if pos then cfg().manaPoint = pos end end,
    Restore = function() if frame then RestorePosition() end end,
    OnEnter = function()
        if not frame or not NS:IsAreaRunning("audit") or not cfg().manaBreak then return end
        preview = true
        MB:Refresh()
    end,
    OnExit = function()
        if not preview then return end
        preview = false
        MB:Refresh()
    end,
})
