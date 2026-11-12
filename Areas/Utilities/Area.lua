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

        -- crushing blows
        if not r.canCrush then
            page.verdictCrush:SetText(string.format(L["VERDICT_NO_CRUSH"], r.mobLevel))
            Kit.SetTextColor(page.verdictCrush, C.muted)
        elseif r.uncrushable then
            local text = L["VERDICT_UNCRUSHABLE"]
            if #r.counted > 0 then
                local without = Avoidance.Compute(snap, { offset = cfg().mobOffset })
                if not without.uncrushable then
                    local b = r.counted[1]
                    text = text .. "  " .. string.format(L["VERDICT_ONLY_WHILE"], BuffName(b), b.duration, b.charges)
                end
            end
            page.verdictCrush:SetText(text)
            Kit.SetTextColor(page.verdictCrush, GOOD)
        else
            page.verdictCrush:SetText(string.format(L["VERDICT_CRUSHABLE"], Pct(r.short)))
            Kit.SetTextColor(page.verdictCrush, C.warn)
        end
        -- crits
        if r.critImmune then
            page.verdictCrit:SetText(string.format(L["VERDICT_CRIT_IMMUNE"], r.mobLevel))
            Kit.SetTextColor(page.verdictCrit, GOOD)
        else
            page.verdictCrit:SetText(string.format(L["VERDICT_CRITABLE"], Pct(r.raw.crit), r.defenseNeeded,
                snap.defense + r.defenseNeeded))
            Kit.SetTextColor(page.verdictCrit, C.warn)
        end
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
