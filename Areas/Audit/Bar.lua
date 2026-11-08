local ADDON_NAME, NS = ...

-- The audit bar, as a checklist of TILES (workspace kb/addons/TankAudit.md "Audit Bar v2"; from TankAuditForever Modules/Bar.lua). A tile is:
--   our SecureActionButton (click when the buff is missing: cast / ask the group / open bags)
--   + our dimmed red "missing" art
--   + a Blizzard aura slot on top (CustomAuraContainer) that draws the real icon, sweep and countdown (red near
--     expiry) whenever the buff is up, live IN COMBAT, even though aura data is secret to addons.
-- Top row: Blizzard Salvation slot (right-click cancels, in combat too) + dispellable-debuff group.
-- Rules learned in-game: build every Blizzard aura frame before PLAYER_LOGIN (layout lock), size aura-group frames
-- yourself, register both click halves on secure buttons. Secure tiles can't be shown/moved in combat, so the
-- layout is decided out of combat (Scanner plan) and frozen during fights; each tile stays live.
local Bar = NS:RegisterModule("AuditBar", "audit")
local Utils, L, D = NS.Utils, NS.L, NS.AuditData

local SIZE = 32
local SPACING = 4
local ROW_GAP = 16
local GROUP_WARN = 60
local CONSUMABLE_WARN = 60

local anchor, mover
local tiles = {}        -- creation order
local tilesByKey = {}
local salvationHolder
local debuffTiles = {}  -- [dispelType] = holder (Blizzard slot + our click catcher)
local built = false
local pendingPlan = nil
local pendingLayout = false
local preview = false
local windowPreview = false   -- the Bulwark window is showing the Audit tab

-- Should a tile be visible? Only when something needs attention: a prompt (stance/healthstone), a missing buff
-- (expiresAt == nil), or a buff inside its warning window. Up-and-fine buffs (expiresAt 0 = no expiry) hide.
local function NeedsAttention(item, now)
    if item.alwaysShow or item.expiresAt == nil then return true end
    return item.expiresAt > 0 and (item.expiresAt - (now or GetTime())) <= (item.warn or 0)
end
Bar.NeedsAttention = NeedsAttention

local function ApplyPosition()
    local p = NS.db.audit.point
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    anchor:SetScale(NS.db.audit.scale)
end

local function SavePosition()
    local point, _, relativePoint, x, y = anchor:GetPoint(1)
    if point then
        NS.db.audit.point = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
end

-- Every tile this class could ever need (created once, at ADDON_LOADED)
local function TileDefs(class)
    local defs = {}
    for _, s in ipairs(D.SELF[class] or {}) do
        if s.stance then
            defs[#defs + 1] = { tileKey = "SELF:" .. s.key, kind = "plain", icon = s.icon }
        else
            defs[#defs + 1] = { tileKey = "SELF:" .. s.key, kind = "aura", ids = s.ids, icon = s.icon,
                warn = s.warn, alert = s.alert and s or nil }
        end
    end
    for _, g in ipairs(D.GROUP) do
        if not (g.skipFor and g.skipFor[class]) then
            local ids = {}
            for _, id in ipairs(g.ids) do ids[#ids + 1] = id end
            for _, id in ipairs(g.greater or {}) do ids[#ids + 1] = id end
            defs[#defs + 1] = { tileKey = "GROUP:" .. g.key, kind = "aura", ids = ids, icon = g.icon, warn = GROUP_WARN }
        end
    end
    for _, key in ipairs(D.BLESSING_ORDER) do
        local b = D.BLESSINGS[key]
        local ids = {}
        for _, id in ipairs(b.ids) do ids[#ids + 1] = id end
        for _, id in ipairs(b.greater or {}) do ids[#ids + 1] = id end
        defs[#defs + 1] = { tileKey = "BLESSING:" .. key, kind = "aura", ids = ids, icon = b.icon, warn = GROUP_WARN }
    end
    defs[#defs + 1] = { tileKey = "CONS:WELL_FED", kind = "aura", ids = D.WELL_FED, icon = D.ICONS.WELL_FED, warn = CONSUMABLE_WARN }
    defs[#defs + 1] = { tileKey = "CONS:ELIXIR", kind = "aura", ids = D.ELIXIRS, icon = D.ICONS.ELIXIR, warn = CONSUMABLE_WARN }
    defs[#defs + 1] = { tileKey = "CONS:FLASK", kind = "aura", ids = D.FLASKS, icon = D.ICONS.FLASK, warn = CONSUMABLE_WARN }
    defs[#defs + 1] = { tileKey = "CONS:WEAPON_BUFF", kind = "enchant", icon = D.ICONS.WEAPON_BUFF, warn = CONSUMABLE_WARN }
    defs[#defs + 1] = { tileKey = "HEALTHSTONE", kind = "plain", icon = D.ICONS.HEALTHSTONE }
    return defs
end

-- Blizzard aura button styling: icon, sweep, countdown whose color turns red under `warn` seconds
local function StyleAuraFrame(frame, warn)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetHideCountdownNumbers(true)
    frame:SetDurationCooldown(cooldown)

    local text = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    text:SetPoint("BOTTOM", frame, "BOTTOM", 0, 1)
    local curve = C_CurveUtil.CreateColorCurve()
    if warn and warn > 0 then
        curve:AddPoint(0, CreateColor(1, 0.15, 0.15, 1))
        curve:AddPoint(warn, CreateColor(1, 0.15, 0.15, 1))
        curve:AddPoint(warn + 0.5, CreateColor(1, 1, 1, 1))
    else
        curve:AddPoint(0, CreateColor(1, 1, 1, 1))
    end
    curve:AddPoint(86400, CreateColor(1, 1, 1, 1))
    frame:SetDurationText(text, {
        textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration },
    })
end

local function NewContainer(parent)
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    container:SetUnit("player")
    return container
end

local HINTS = { spell = "HINT_CAST", request = "HINT_REQUEST", bags = "HINT_BAGS" }

-- Our tooltip (visible tiles only: hidden tiles have their mouse disabled)
local function ShowTooltip(tile)
    local item = tile.item
    if not item then return end
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:SetText(item.label or "?", 1, 1, 1)
    if item.expiresAt and item.expiresAt > 0 then
        GameTooltip:AddLine(string.format(L["HINT_EXPIRING"], Utils.FormatTime(item.expiresAt - GetTime())), 1, 0.82, 0)
    else
        GameTooltip:AddLine(L["HINT_MISSING"], 1, 0.3, 0.3)
    end
    local hint = item.action and HINTS[item.action.type]
    if hint then GameTooltip:AddLine(L[hint], 0.6, 0.8, 1) end
    GameTooltip:Show()
end

-- Our tiles only use the left button. The right button passes through to whatever is beneath (the game world:
-- hold right-click to turn), even over a transparent tile that keeps its mouse in combat (the debuff click-catchers
-- always do; EnableMouse can't change in combat). Protected: set once at load, out of combat.
local function PassRightClick(button)
    pcall(button.SetPassThroughButtons, button, "RightButton")
end

local function CreateTile(def, index)
    local tile = CreateFrame("Button", "Bulwark_AuditTile" .. index, anchor, "SecureActionButtonTemplate")
    tile:SetSize(SIZE, SIZE)
    -- Addon secure buttons act on mouse DOWN by default: register both halves (kb/gotchas.md#secure-clicks)
    tile:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    PassRightClick(tile)
    tile.def = def

    tile.art = tile:CreateTexture(nil, "BACKGROUND")
    tile.art:SetAllPoints()
    tile.art:SetTexture(def.icon or D.ICONS.UNKNOWN)
    tile.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tile.art:SetDesaturated(true)
    tile.art:SetVertexColor(1, 0.35, 0.35)
    tile:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    tile:SetScript("OnEnter", ShowTooltip)
    tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tile:HookScript("OnClick", function(self, _, down)
        if down then return end -- the hook sees both click halves; act once
        NS.AuditRequests:OnClick(self.item)
    end)

    -- Blizzard live display on top (a failure degrades the tile to a plain out-of-combat prompt)
    local ok, err = pcall(function()
        if def.kind == "aura" then
            local container = NewContainer(tile)
            container:SetAllPoints(tile)
            local slot = container:AddAuraSlot("tile", "HELPFUL",
                { candidateFilters = { includeSpellIDs = Utils.ToSet(def.ids) } })
            slot:SetAllPoints(tile)
            StyleAuraFrame(slot, def.warn)
            -- Buff tiles that are fine wait transparent; Blizzard's button would still show its tooltip on hover
            -- [in-game]. Mouse off: no phantom tooltips, and clicks on a visible (expiring) tile reach our button.
            pcall(slot.EnableMouse, slot, false)
            tile.blizzardSlot = slot
        elseif def.kind == "enchant" then
            local container = NewContainer(tile)
            container:SetPoint("TOPLEFT", tile, "TOPLEFT")
            container:SetSize(SIZE, SIZE)
            local mainHand = AuraContainerItemEnchantmentSlot and AuraContainerItemEnchantmentSlot.MainHand or 0
            local frame = container:AddItemEnchantment(mainHand, {
                initializeFrame = function(f) f:SetSize(SIZE, SIZE) end,
            })
            if frame then
                StyleAuraFrame(frame, def.warn)
                pcall(frame.EnableMouse, frame, false) -- same as aura slots: no tooltip on a hidden tile
                tile.blizzardSlot = frame
            end
        end
    end)
    if not ok then
        NS:Print("|cffFF4444Live display unavailable for %s:|r %s", def.tileKey, tostring(err))
    end

    -- Alert glow (SelfAlert), our own frame layered above Blizzard's
    local glowFrame = CreateFrame("Frame", nil, tile)
    glowFrame:SetAllPoints()
    glowFrame:SetFrameLevel(tile:GetFrameLevel() + 10)
    tile.glow = glowFrame:CreateTexture(nil, "OVERLAY")
    tile.glow:SetPoint("TOPLEFT", -6, 6)
    tile.glow:SetPoint("BOTTOMRIGHT", 6, -6)
    tile.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    tile.glow:SetBlendMode("ADD")
    tile.glow:SetVertexColor(1, 0.1, 0.1)
    tile.glow:Hide()

    tile:Hide()
    return tile
end

-- Top row: Salvation slot (Blizzard right-click cancel) + dispellable debuffs group
local function CreateTopRow()
    local y = SIZE + ROW_GAP
    salvationHolder = CreateFrame("Frame", "Bulwark_SalvationHolder", anchor)
    salvationHolder:SetSize(SIZE, SIZE)
    salvationHolder:SetPoint("CENTER", anchor, "CENTER", -(SIZE / 2 + SPACING), y)
    local ok, err = pcall(function()
        local container = NewContainer(salvationHolder)
        container:SetAllPoints(salvationHolder)
        local ids = {}
        for _, def in ipairs(D.UNWANTED) do
            for _, id in ipairs(def.ids) do ids[id] = true end
        end
        local slot = container:AddAuraSlot("unwanted", "HELPFUL", { candidateFilters = { includeSpellIDs = ids } })
        slot:SetAllPoints(salvationHolder)
        slot:SetCancelAuraButtons("RightButtonUp")
        StyleAuraFrame(slot, 0)
        local tag = slot:CreateFontString(nil, "OVERLAY")
        tag:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        tag:SetPoint("BOTTOM", slot, "TOP", 0, 1)
        tag:SetText("|cffFF2222" .. L["TAG_CANCEL"] .. "|r")
    end)
    if not ok then NS:Print("|cffFF4444Salvation display unavailable:|r %s", tostring(err)) end

    -- One tile per dispel type: Blizzard slot (that type's debuff, live in combat) UNDER our transparent secure
    -- button. Blizzard aura buttons swallow clicks, so ours sits on top: click = own dispel or ask the group.
    -- Mouse motion is passed through so Blizzard's debuff tooltip still works.
    for _, dtype in ipairs(D.DISPEL_ORDER) do
        local holder = CreateFrame("Frame", "Bulwark_AuditDebuff" .. dtype, anchor)
        holder:SetSize(SIZE, SIZE)
        -- Marks the clickable spot; shown only in preview (unlocked bar / options open), per the user's choice
        holder.bg = holder:CreateTexture(nil, "BACKGROUND")
        holder.bg:SetAllPoints()
        holder.bg:SetColorTexture(0, 0, 0, 0.35)
        holder.bg:Hide()
        local dok, derr = pcall(function()
            local container = NewContainer(holder)
            container:SetAllPoints(holder)
            local slot = container:AddAuraSlot("debuff", "HARMFUL",
                { candidateFilters = { includeDispelTypes = { [dtype] = true } } })
            slot:SetAllPoints(holder)
            StyleAuraFrame(slot, 0)
        end)
        if not dok then NS:Print("|cffFF4444Debuff display unavailable:|r %s", tostring(derr)) end

        local catcher = CreateFrame("Button", "Bulwark_AuditDebuffClick" .. dtype, holder, "SecureActionButtonTemplate")
        catcher:SetAllPoints(holder)
        catcher:SetFrameLevel(holder:GetFrameLevel() + 20)
        catcher:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        PassRightClick(catcher)
        catcher.dispelType = dtype
        if not pcall(catcher.SetPropagateMouseMotion, catcher, true) then
            -- Fallback: our own tooltip if motion can't pass through to Blizzard's button
            catcher:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L[dtype], 1, 1, 1)
                GameTooltip:AddLine(self.item and self.item.action.type == "spell" and L["HINT_DISPEL_SELF"]
                    or L["HINT_DISPEL_REQUEST"], 0.6, 0.8, 1)
                GameTooltip:Show()
            end)
            catcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        catcher:HookScript("OnClick", function(self, _, down)
            if down then return end
            NS.AuditRequests:OnClick(self.item)
        end)
        holder.catcher = catcher
        holder:Hide()
        debuffTiles[dtype] = holder
    end
end

local function CreateMover()
    mover = CreateFrame("Frame", nil, anchor)
    mover:SetPoint("TOPLEFT", anchor, "TOPLEFT", -6, 6)
    mover:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 6, -6)
    mover:SetFrameLevel(anchor:GetFrameLevel() + 30)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 1, 0.5, 0.25)
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    text:SetText(L["BAR_DRAG_HINT"])
    mover:SetScript("OnDragStart", function()
        if not InCombatLockdown() then anchor:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        SavePosition()
    end)
    mover:SetShown(not NS.db.audit.locked)
end

local function SetupTile(tile, item)
    tile.item = item
    local action = item.action or {}
    if action.type == "spell" then
        tile:SetAttribute("type", "spell")
        tile:SetAttribute("spell", action.spell)
        tile:SetAttribute("unit", action.unit)
    else
        tile:SetAttribute("type", nil)
        tile:SetAttribute("spell", nil)
        tile:SetAttribute("unit", nil)
    end
end

local function PreviewPlan()
    local items = {}
    for _, tile in ipairs(tiles) do
        items[#items + 1] = { tileKey = tile.def.tileKey, key = tile.def.tileKey, label = L["PREVIEW"] }
    end
    local dispelActions = {}
    for _, dtype in ipairs(D.DISPEL_ORDER) do dispelActions[dtype] = { type = "request" } end
    return { tiles = items, salvation = true, dispelActions = dispelActions }
end

-- Show and arrange tiles for a plan (out of combat only; in combat the plan waits)
function Bar:Apply(plan)
    if not built then return end
    if InCombatLockdown() then
        pendingPlan = plan
        return
    end
    pendingPlan = nil
    self.plan = plan
    if preview then plan = PreviewPlan() end
    plan = plan or { tiles = {} }

    -- "No tiles = all good": tiles needing attention are packed and centered; the others are placed after them,
    -- shown but transparent and mouse-disabled, so they can fade in during combat (alpha isn't protected; showing,
    -- moving and EnableMouse are).
    local now = GetTime()
    local attention, waiting = {}, {}
    for _, item in ipairs(plan.tiles) do
        local tile = tilesByKey[item.tileKey]
        if tile then
            local entry = { tile = tile, item = item }
            if preview or NeedsAttention(item, now) then
                attention[#attention + 1] = entry
            else
                waiting[#waiting + 1] = entry
            end
        end
    end

    local shown = {}
    local x = -((#attention * SIZE) + ((#attention - 1) * SPACING)) / 2 + SIZE / 2
    local function Place(entry, visible)
        SetupTile(entry.tile, entry.item)
        entry.tile:ClearAllPoints()
        entry.tile:SetPoint("CENTER", anchor, "CENTER", x, 0)
        entry.tile:SetAlpha(visible and 1 or 0)
        entry.tile:EnableMouse(visible)
        entry.tile:Show()
        shown[entry.tile] = true
        x = x + SIZE + SPACING
    end
    for _, entry in ipairs(attention) do Place(entry, true) end
    for _, entry in ipairs(waiting) do Place(entry, false) end
    for _, tile in ipairs(tiles) do
        if not shown[tile] then
            tile.item = nil
            if tile:IsShown() then tile:Hide() end
        end
    end

    -- Top row: Salvation left of center, debuff tiles (types someone can remove) to the right
    salvationHolder:SetShown(plan.salvation and true or false)
    local dx = SPACING / 2 + SIZE / 2
    for _, dtype in ipairs(D.DISPEL_ORDER) do
        local holder = debuffTiles[dtype]
        local action = plan.dispelActions and plan.dispelActions[dtype]
        if action then
            local catcher = holder.catcher
            catcher.item = { key = "DEBUFF", kind = "debuff", dispelType = dtype, label = L[dtype], action = action }
            catcher:SetAttribute("type", action.type == "spell" and "spell" or nil)
            catcher:SetAttribute("spell", action.spell)
            catcher:SetAttribute("unit", action.unit)
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", anchor, "CENTER", dx, SIZE + ROW_GAP)
            holder.bg:SetShown(preview)
            holder:Show()
            dx = dx + SIZE + SPACING
        else
            holder.bg:Hide()
            if holder:IsShown() then holder:Hide() end
        end
    end
end

function Bar:SetPreview(enabled)
    preview = enabled and true or false
    self:Apply(self.plan or NS.AuditScanner.plan)
end

-- Preview (every tile shown) while the bar is unlocked or the Bulwark window shows the Audit tab.
local function WantPreview()
    return (not NS.db.audit.locked) or windowPreview
end

function Bar:SetWindowPreview(enabled)
    windowPreview = enabled and true or false
    if built and NS:IsAreaRunning("audit") and preview ~= WantPreview() then self:SetPreview(WantPreview()) end
end

function Bar:SetLocked(locked, quiet)
    NS.db.audit.locked = locked and true or false
    if mover then mover:SetShown(not locked) end
    if built then self:SetPreview(WantPreview()) end
    if not quiet then NS:Print(locked and L["BAR_LOCKED"] or L["BAR_UNLOCKED"]) end
end

function Bar:ResetPosition()
    NS.db.audit.point = NS.CopyTable(NS.DefaultConfig.audit.point)
    if not built then return end
    if InCombatLockdown() then
        pendingLayout = true
        NS:Print(L["AUDIT_IN_COMBAT_LATER"])
        return
    end
    ApplyPosition()
    NS:Print(L["BAR_RESET"])
end

function Bar:SetScale(scale)
    NS.db.audit.scale = scale
    if InCombatLockdown() then pendingLayout = true return end
    if anchor then anchor:SetScale(scale) end
end

-- Visibility ticker: fades tiles in when they enter their warning window (or go missing), in combat too.
-- Out of combat the Scanner replans every few seconds and re-packs; here we only adjust alpha (never protected).
-- In combat nothing updates a tile's expiry except your own casts (SelfAlert, `ownCast` tiles), so only those can
-- fade back out after a recast. Other buffs keep their pre-combat estimate: once shown they stay shown, and
-- Blizzard's slot on top shows the real state (e.g. lit with a fresh timer if someone refreshed it).
local function UpdateVisibility()
    if not built or preview or not NS:IsAreaRunning("audit") then return end
    local now, inCombat = GetTime(), InCombatLockdown()
    local repack = false
    for _, tile in ipairs(tiles) do
        local item = tile.item
        if item and tile:IsShown() then
            local needs = NeedsAttention(item, now)
            local visible = tile:GetAlpha() > 0
            if needs and not visible then
                tile:SetAlpha(1)
                if not inCombat then repack = true end
            elseif not needs and visible then
                tile:SetAlpha(0)
                if not inCombat then repack = true end
            end
        end
    end
    if repack then NS.AuditScanner:Queue() end
end

local eventFrame = CreateFrame("Frame", "Bulwark_AuditBarEventFrame")
eventFrame:SetScript("OnEvent", function()
    if pendingLayout then
        pendingLayout = false
        ApplyPosition()
        anchor:SetShown(NS:IsAreaRunning("audit"))
    end
    if pendingPlan then Bar:Apply(pendingPlan) end
end)

-- Built at ADDON_LOADED: Blizzard aura frames accept layout calls only until PLAYER_LOGIN.
function Bar:OnInitialize()
    local _, class = UnitClass("player")
    if not class or not D.SELF[class] then return end
    if InCombatLockdown() then
        NS:Print(L["RELOADED_IN_COMBAT"])
        return
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end

    anchor = CreateFrame("Frame", "Bulwark_AuditBar", UIParent)
    anchor:SetSize(10 * (SIZE + SPACING), SIZE * 2 + ROW_GAP)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    ApplyPosition()
    -- Hidden until the Audit area starts (it may stay off, or wait while TankAuditForever is loaded).
    anchor:Hide()

    for i, def in ipairs(TileDefs(class)) do
        local tile = CreateTile(def, i)
        tiles[#tiles + 1] = tile
        tilesByKey[def.tileKey] = tile
    end
    CreateTopRow()
    CreateMover()
    preview = not NS.db.audit.locked
    built = true
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    C_Timer.NewTicker(0.5, UpdateVisibility)
end

function Bar:OnEnable()
    if not built then return end
    preview = WantPreview()
    if InCombatLockdown() then pendingLayout = true return end
    anchor:Show()
end

function Bar:IsBuilt() return built end

function Bar:OnDisable()
    if not built then return end
    if InCombatLockdown() then pendingLayout = true return end
    preview = false
    self:Apply({ tiles = {} })
    anchor:Hide()
end

-- For SelfAlert, tests and /bwk audit status
function Bar:GetTile(tileKey) return tilesByKey[tileKey] end
function Bar:GetTiles() return tiles end
function Bar:GetAnchor() return anchor end
function Bar:GetDebuffTile(dispelType) return debuffTiles[dispelType] end
function Bar:GetSalvationHolder() return salvationHolder end
