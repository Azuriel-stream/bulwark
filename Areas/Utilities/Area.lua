local ADDON_NAME, NS = ...
local L, Kit, Avoidance = NS.L, NS.Kit, NS.Avoidance
local C = Kit.C

-- Utilities: tank helpers that only read the character (kb/addons/Bulwark-Utilities.md). Step 1: Avoidance page.
local area = NS:RegisterArea({
    key = "utilities",
    order = 4,
    title = L["AREA_UTILITIES"],
    desc = L["AREA_UTILITIES_DESC"],
    icon = "tab_utilities",
})

NS.DefaultConfig.utilities = {
    mobOffset = 3,                                      -- attacker level above the player: 3 = raid boss
    count = { shieldBlock = false, holyShield = false }, -- block cooldowns counted in the table
}

local function cfg() return NS.db.utilities end

local function Card(parent, title, y, height)
    local card = Kit.Card(parent, title)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card:SetHeight(height)
    return card
end

-- Segment colours of the attack table bar (and the legend squares).
local COLORS = {
    miss  = { 0.55, 0.62, 0.70 },
    dodge = { 0.20, 0.72, 0.42 },
    parry = { 0.16, 0.62, 0.66 },
    block = { 0.25, 0.48, 0.85 },
    crit  = { 1.00, 0.55, 0.20 },
    crush = { 0.85, 0.20, 0.18 },
    hit   = { 0.30, 0.31, 0.34 },
}
local GOOD = { 0.30, 0.85, 0.45, 1 }
local BAR_W = 600

local function Pct(v) return string.format("%.2f%%", v) end

local function BuffFor(class)
    for _, buff in ipairs(Avoidance.BUFFS) do
        if buff.class == class then return buff end
    end
end

local function BuffName(buff) return L["BUFF_" .. buff.key] end

-- The two verdict lines (page.verdictCrush / page.verdictCrit) for a Compute result r of snapshot snap.
local function ShowVerdicts(page, r, snap)
    if not r.canCrush then
        page.verdictCrush:SetText(string.format(L["VERDICT_NO_CRUSH"], r.mobLevel))
        Kit.SetTextColor(page.verdictCrush, C.muted)
    elseif r.uncrushable then
        local text = L["VERDICT_UNCRUSHABLE"]
        if #r.counted > 0 and not Avoidance.Compute(snap, { offset = cfg().mobOffset }).uncrushable then
            local b = r.counted[1]
            text = text .. "  " .. string.format(L["VERDICT_ONLY_WHILE"], BuffName(b), b.duration, b.charges)
        end
        page.verdictCrush:SetText(text)
        Kit.SetTextColor(page.verdictCrush, GOOD)
    else
        page.verdictCrush:SetText(string.format(L["VERDICT_CRUSHABLE"], Pct(r.short)))
        Kit.SetTextColor(page.verdictCrush, C.warn)
    end
    if r.critImmune then
        page.verdictCrit:SetText(string.format(L["VERDICT_CRIT_IMMUNE"], r.mobLevel))
        Kit.SetTextColor(page.verdictCrit, GOOD)
    else
        page.verdictCrit:SetText(string.format(L["VERDICT_CRITABLE"], Pct(r.raw.crit), r.defenseNeeded,
            snap.defense + r.defenseNeeded))
        Kit.SetTextColor(page.verdictCrit, C.warn)
    end
end

-- Legend row: colour square, label, value right-aligned.
local function Row(parent, x, y, key, label)
    local sq = parent:CreateTexture(nil, "ARTWORK")
    sq:SetSize(10, 10)
    sq:SetPoint("TOPLEFT", x, y - 2)
    local c = COLORS[key]
    if c then sq:SetColorTexture(c[1], c[2], c[3], 1) else sq:SetColorTexture(0, 0, 0, 0) end
    local name = Kit.Text(parent, 12)
    name:SetPoint("TOPLEFT", x + 16, y)
    name:SetText(label)
    local value = Kit.Text(parent, 12)
    value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + 230, y)
    value:SetJustifyH("RIGHT")
    return { name = name, value = value }
end

---------------------------------------------------------------------------------------------------------------
-- Avoidance page
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "avoidance",
    title = L["PAGE_AVOIDANCE"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_AVOIDANCE"], L["AVOIDANCE_DESC"])

        -- Attacker level (radio row)
        local against = Card(parent, L["CARD_AGAINST"], y, 72)
        page.levels = {}
        for offset = 0, 3 do
            local cb = Kit.Checkbox(against, "", nil, function()
                cfg().mobOffset = offset
                page:refresh()
            end)
            cb:SetPoint("TOPLEFT", 12 + offset * 150, -38)
            page.levels[offset] = cb
        end

        -- Attack table: bar, legend, verdicts
        local tbl = Card(parent, L["CARD_ATTACK_TABLE"], y - 82, 214)
        page.frozen = Kit.Text(tbl, 11, C.warn)
        page.frozen:SetPoint("TOPRIGHT", -14, -14)
        page.bar = CreateFrame("Frame", nil, tbl)
        page.bar:SetSize(BAR_W, 16)
        page.bar:SetPoint("TOPLEFT", 16, -42)
        Kit.Fill(page.bar, C.panel)
        page.segments = {}
        local order = { "miss", "dodge", "parry", "block", "crit", "crush", "hit" }
        for _, key in ipairs(order) do
            local seg = page.bar:CreateTexture(nil, "ARTWORK")
            local c = COLORS[key]
            seg:SetColorTexture(c[1], c[2], c[3], 1)
            seg:SetHeight(16)
            page.segments[key] = seg
        end
        page.rows = {}
        local left = { "miss", "dodge", "parry", "block" }
        for i, key in ipairs(left) do
            page.rows[key] = Row(tbl, 16, -70 - (i - 1) * 20, key, L["AV_" .. key])
        end
        page.rows.total = Row(tbl, 16, -154, nil, L["AV_TOTAL"])
        Kit.SetTextColor(page.rows.total.name, C.goldText)
        Kit.SetTextColor(page.rows.total.value, C.goldText)
        for i, key in ipairs({ "crit", "crush", "hit" }) do
            page.rows[key] = Row(tbl, 330, -70 - (i - 1) * 20, key, L["AV_" .. key])
        end
        page.verdictCrush = Kit.Text(tbl, 12)
        page.verdictCrush:SetPoint("TOPLEFT", 16, -176)
        page.verdictCrush:SetWidth(620)
        page.verdictCrit = Kit.Text(tbl, 12)
        page.verdictCrit:SetPoint("TOPLEFT", 16, -194)
        page.verdictCrit:SetWidth(620)

        -- Block cooldown for this class
        local cd = Card(parent, L["CARD_COOLDOWNS"], y - 306, 66)
        local buff = BuffFor(NS.playerClass)
        if buff then
            page.buff = buff
            page.count = Kit.Checkbox(cd, string.format(L["OPT_COUNT_BUFF"], BuffName(buff), buff.block,
                buff.duration, buff.charges), L["OPT_COUNT_BUFF_DESC"], function(checked)
                cfg().count[buff.key] = checked
                page:refresh()
            end)
            page.count:SetPoint("TOPLEFT", 12, -36)
        end
        page.cdNote = Kit.Text(cd, 12, C.muted)
        page.cdNote:SetPoint("TOPLEFT", 16, -42)

        NS:On("AVOIDANCE_CHANGED", function()
            if page.frame and page.frame:IsShown() then page:refresh() end
        end)
    end,
    refresh = function(page)
        local snap, frozen = Avoidance:Get()
        local level = snap and snap.level or UnitLevel("player") or 60
        for offset, cb in pairs(page.levels) do
            local text = offset == 3 and string.format(L["MOB_LEVEL_BOSS"], level + offset)
                or string.format(L["MOB_LEVEL"], level + offset)
            cb.Text:SetText(text)
            cb:SetChecked(cfg().mobOffset == offset)
        end

        -- cooldown checkbox
        if page.buff then
            local known = snap and snap.known[page.buff.key]
            local usable = known and snap.hasShield
            page.count:SetShown(usable and true or false)
            page.count:SetChecked(cfg().count[page.buff.key] and true or false)
            page.cdNote:SetShown(not usable)
            if not known then
                page.cdNote:SetText(string.format(L["CD_NOT_LEARNED"], BuffName(page.buff)))
            elseif not snap.hasShield then
                page.cdNote:SetText(L["CD_NO_SHIELD"])
            end
        else
            page.cdNote:SetText(L["CD_NONE_FOR_CLASS"])
        end

        page.frozen:SetText(frozen and snap and L["AV_FROZEN"] or "")
        if not snap then
            for _, row in pairs(page.rows) do row.value:SetText("-") end
            for _, seg in pairs(page.segments) do seg:Hide() end
            page.verdictCrush:SetText(L["AV_NO_DATA"])
            Kit.SetTextColor(page.verdictCrush, C.muted)
            page.verdictCrit:SetText("")
            return
        end

        local r = Avoidance.Compute(snap, { offset = cfg().mobOffset, count = cfg().count })
        local x = 0
        for _, key in ipairs({ "miss", "dodge", "parry", "block", "crit", "crush", "hit" }) do
            local seg, w = page.segments[key], BAR_W * r.table[key] / 100
            seg:ClearAllPoints()
            if w >= 0.5 then
                seg:SetPoint("TOPLEFT", page.bar, "TOPLEFT", x, 0)
                seg:SetWidth(w)
                seg:Show()
                x = x + w
            else
                seg:Hide()
            end
        end
        for _, key in ipairs({ "miss", "dodge", "parry", "crit", "crush" }) do
            page.rows[key].value:SetText(Pct(r.table[key]))
        end
        page.rows.block.value:SetText(snap.hasShield and Pct(r.table.block) or L["AV_NO_SHIELD"])
        page.rows.hit.value:SetText(Pct(r.table.hit))
        page.rows.total.value:SetText(Pct(r.total))

        ShowVerdicts(page, r, snap)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- What if: stat changes on top of the current snapshot
---------------------------------------------------------------------------------------------------------------

local WHATIF = {
    { key = "defense", min = -50, max = 150, step = 1, fmt = "%+.0f" },
    { key = "agility", min = -50, max = 200, step = 1, fmt = "%+.0f" },
    { key = "dodge", min = -5, max = 10, step = 0.5, fmt = "%+.1f%%" },
    { key = "parry", min = -5, max = 10, step = 0.5, fmt = "%+.1f%%" },
    { key = "block", min = -5, max = 10, step = 0.5, fmt = "%+.1f%%" },
}
local MORE_IS_BETTER = { miss = true, dodge = true, parry = true, block = true, total = true }

-- Compare row: colour square, label, "now -> what-if", change.
local function CompareRow(parent, x, y, key)
    local row = Row(parent, x, y, key, L[key == "total" and "AV_TOTAL" or ("AV_" .. key)])   -- total: no colour
    if key == "total" then
        -- no colour square: the label starts at the left edge ([in-game] it touched "100.96 > 126.35%")
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", x, y)
    end
    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + 240, y)
    row.change = Kit.Text(parent, 12)
    row.change:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + 298, y)
    row.change:SetJustifyH("RIGHT")
    return row
end

NS:AddPage(area.key, {
    key = "whatif",
    title = L["PAGE_WHATIF"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_WHATIF"], L["WHATIF_DESC"])
        page.delta = {}
        local adjust = Card(parent, L["CARD_ADJUST"], y, 200)
        page.sliders = {}
        for i, def in ipairs(WHATIF) do
            page.delta[def.key] = 0
            local slider = Kit.Slider(adjust, L["WI_" .. def.key], def.min, def.max, def.step,
                function(v) return string.format(def.fmt, v) end,
                function(v)
                    page.delta[def.key] = v
                    if page.ready then page:refresh() end
                end)
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            slider:SetPoint("TOPLEFT", 12 + col * 318, -62 - row * 54)
            page.sliders[def.key] = slider
        end
        page.reset = Kit.Button(adjust, L["BTN_RESET"], 120, function()
            for _, def in ipairs(WHATIF) do page.sliders[def.key]:SetValue(0) end
            page:refresh()
        end)
        page.reset:SetPoint("TOPLEFT", 349, -160)

        local result = Card(parent, "", y - 210, 186)
        page.resultTitle = result.title
        page.frozen = Kit.Text(result, 11, C.warn)
        page.frozen:SetPoint("TOPRIGHT", -14, -14)
        page.rows = {}
        for i, key in ipairs({ "miss", "dodge", "parry", "block", "total" }) do
            page.rows[key] = CompareRow(result, 16, -42 - (i - 1) * 19, key)
        end
        Kit.SetTextColor(page.rows.total.name, C.goldText)
        for i, key in ipairs({ "crit", "crush", "hit" }) do
            page.rows[key] = CompareRow(result, 330, -42 - (i - 1) * 19, key)
        end
        page.verdictCrush = Kit.Text(result, 12)
        page.verdictCrush:SetPoint("TOPLEFT", 16, -142)
        page.verdictCrush:SetWidth(620)
        page.verdictCrit = Kit.Text(result, 12)
        page.verdictCrit:SetPoint("TOPLEFT", 16, -161)
        page.verdictCrit:SetWidth(620)

        for _, def in ipairs(WHATIF) do page.sliders[def.key]:SetValue(0) end
        page.ready = true
        NS:On("AVOIDANCE_CHANGED", function()
            if page.frame and page.frame:IsShown() then page:refresh() end
        end)
    end,
    refresh = function(page)
        local snap, frozen = Avoidance:Get()
        page.frozen:SetText(frozen and snap and L["AV_FROZEN"] or "")
        if not snap then
            page.resultTitle:SetText(L["CARD_WHATIF_RESULT_NONE"])
            for _, row in pairs(page.rows) do row.value:SetText("-"); row.change:SetText("") end
            page.verdictCrush:SetText(L["AV_NO_DATA"])
            Kit.SetTextColor(page.verdictCrush, C.muted)
            page.verdictCrit:SetText("")
            return
        end
        local opts = { offset = cfg().mobOffset, count = cfg().count }
        local changed = Avoidance.Apply(snap, page.delta)
        local now, wi = Avoidance.Compute(snap, opts), Avoidance.Compute(changed, opts)
        page.resultTitle:SetText(string.format(L["CARD_WHATIF_RESULT"], wi.mobLevel))
        for key, row in pairs(page.rows) do
            local a = key == "total" and now.total or now.table[key]
            local b = key == "total" and wi.total or wi.table[key]
            if key == "block" and not snap.hasShield then
                row.value:SetText(L["AV_NO_SHIELD"])
                row.change:SetText("")
            else
                row.value:SetText(string.format("%.2f  >  %.2f%%", a, b))
                local d = b - a
                if math.abs(d) < 0.005 then
                    row.change:SetText("")
                else
                    row.change:SetText(string.format("%+.2f", d))
                    local good = (d > 0) == (MORE_IS_BETTER[key] == true)
                    -- Past 100 % the roll runs out: block (then crit, crush) shrinks because the outcomes above it
                    -- grew, not because it got worse. Grey when the uncapped value moved the other way.
                    local rawD = now.raw[key] and (wi.raw[key] - now.raw[key])
                    local capped = rawD and (math.abs(rawD) < 0.005 or (rawD > 0) ~= (d > 0))
                    Kit.SetTextColor(row.change, capped and C.muted or (good and GOOD or C.warn))
                end
            end
        end
        ShowVerdicts(page, wi, changed)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- /bwk utilities ...
---------------------------------------------------------------------------------------------------------------

area.commandHelp = {
    "|cffffd160/bwk utilities avoid|r  " .. L["HELP_UTIL_AVOID"],
}

function area.command(args)
    local cmd = (args:match("^(%S*)") or ""):lower()
    if cmd == "avoid" then
        local snap, frozen = Avoidance:Get()
        if not snap then NS:Print(L["AV_NO_DATA"]) return end
        local r = Avoidance.Compute(snap, { offset = cfg().mobOffset, count = cfg().count })
        NS:Print(L["AV_STATUS"], r.mobLevel, frozen and (" " .. L["AV_FROZEN"]) or "")
        print(string.format("  defense %d, sheet dodge %.2f / parry %.2f / block %.2f, shield %s",
            snap.defense, snap.dodge, snap.parry, snap.block, tostring(snap.hasShield)))
        local parts = {}
        for _, key in ipairs({ "miss", "dodge", "parry", "block", "crit", "crush", "hit" }) do
            parts[#parts + 1] = key .. " " .. Pct(r.table[key])
        end
        print("  " .. table.concat(parts, ", "))
        print(string.format("  total %s, uncrushable %s, crit immune %s (need %d)", Pct(r.total),
            tostring(r.uncrushable), tostring(r.critImmune), r.defenseNeeded))
    else
        for _, line in ipairs(area.commandHelp) do print("  " .. line) end
    end
end
