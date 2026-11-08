local ADDON_NAME, NS = ...
local L, Kit = NS.L, NS.Kit
local C = Kit.C

-- Settings tab (always on, no switch): area switches, window and minimap, diagnostics, about.
local area = NS:RegisterArea({
    key = "settings",
    order = 100,
    title = L["AREA_SETTINGS"],
    icon = "tab_settings",
    switch = false,
})

-- Card stretched to the page width at y; returns the card.
local function PlaceCard(parent, title, y, height)
    local card = Kit.Card(parent, title)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card:SetHeight(height)
    return card
end

---------------------------------------------------------------------------------------------------------------
-- Areas: one row per area with its switch
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "areas",
    title = L["PAGE_AREAS"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_AREAS"], L["PAGE_AREAS_DESC"])
        page.rows = {}
        for _, a in ipairs(NS.areas) do
            if a.switch then
                local row = PlaceCard(parent, nil, y, 76)
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(44, 44)
                icon:SetPoint("LEFT", 14, 0)
                icon:SetTexture(Kit.MEDIA .. a.icon)
                local name = Kit.Text(row, 15, C.goldText)
                name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -2)
                name:SetText(a.title)
                local desc = Kit.Text(row, 12, C.muted)
                desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
                desc:SetPoint("RIGHT", row, "RIGHT", -150, 0)
                desc:SetText(a.desc)
                row.status = Kit.Text(row, 11, C.muted)
                row.status:SetPoint("RIGHT", row, "RIGHT", -76, 0)
                row.switch = Kit.Switch(row, function(_, wanted)
                    NS:SetAreaEnabled(a.key, wanted)
                    page:refresh()
                end)
                row.switch:SetPoint("RIGHT", -16, 0)
                row.area = a
                table.insert(page.rows, row)
                y = y - 84
            end
        end
        local note = Kit.Paragraph(parent, L["AREAS_NOTE"], 600, 11, C.muted)
        note:SetPoint("TOPLEFT", 0, y - 4)
    end,
    refresh = function(page)
        for _, row in ipairs(page.rows) do
            local key = row.area.key
            row.switch:SetOn(NS:IsAreaEnabled(key))
            local status = NS:AreaStatus(key)
            if status == "blocked" then
                row.status:SetText("|cffff8c33" .. string.format(L["STATUS_WAITING_FOR"], NS:AreaBlockedBy(key) or "?") .. "|r")
            elseif status == "on" then
                row.status:SetText("|cff00c070" .. L["STATUS_ON"] .. "|r")
            else
                row.status:SetText(L["STATUS_OFF"])
            end
        end
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Window: scale, position, minimap button
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "window",
    title = L["PAGE_WINDOW"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_WINDOW"], L["PAGE_WINDOW_DESC"])

        local win = PlaceCard(parent, L["CARD_WINDOW"], y, 130)
        page.scale = Kit.Slider(win, L["OPT_SCALE"], NS.Window.MIN_SCALE * 100, NS.Window.MAX_SCALE * 100, 5,
            function(v) return string.format("%d%%", v) end,
            function(v) NS.Window:SetScale(v / 100) end, true)
        page.scale:SetPoint("TOPLEFT", 12, -66)
        local reset = Kit.Button(win, L["BTN_RESET_POSITION"], 150, function()
            NS.Window:SetScale(1)
            NS.Window:ResetPosition()
            page:refresh()
        end)
        reset:SetPoint("TOPLEFT", 300, -64)
        Kit.Tooltip(reset, L["BTN_RESET_POSITION"], L["BTN_RESET_POSITION_TIP"])
        local hint = Kit.Text(win, 11, C.muted)
        hint:SetPoint("TOPLEFT", 16, -100)
        hint:SetText(L["WINDOW_HINT"])

        local mini = PlaceCard(parent, L["CARD_MINIMAP"], y - 140, 96)
        page.minimap = Kit.Checkbox(mini, L["OPT_MINIMAP"], L["OPT_MINIMAP_TIP"], function(checked)
            NS.MinimapButton:SetEnabled(checked)
        end)
        page.minimap:SetPoint("TOPLEFT", 12, -38)
        local mhint = Kit.Text(mini, 11, C.muted)
        mhint:SetPoint("TOPLEFT", 16, -70)
        mhint:SetText(L["MINIMAP_HINT"])
    end,
    refresh = function(page)
        page.scale:SetValue((NS.db.ui.scale or 1) * 100)
        page.minimap:SetChecked(not NS.db.minimap.hide)
    end,
})

---------------------------------------------------------------------------------------------------------------
-- Debug: trace, CVars, recorded errors, last blocked action
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "debug",
    title = L["PAGE_DEBUG"],
    build = function(page, parent)
        local y = Kit.PageHeader(parent, L["PAGE_DEBUG"], L["PAGE_DEBUG_DESC"])

        local diag = PlaceCard(parent, L["CARD_DIAGNOSTICS"], y, 104)
        page.trace = Kit.Checkbox(diag, L["OPT_DEBUG_TRACE"], L["OPT_DEBUG_TRACE_TIP"], function(checked)
            NS.db.debug = checked
        end)
        page.trace:SetPoint("TOPLEFT", 12, -38)
        page.cvars = Kit.Checkbox(diag, L["OPT_DEBUG_CVARS"], L["OPT_DEBUG_CVARS_TIP"], function(checked)
            NS:SetDebugCVars(checked)
        end)
        page.cvars:SetPoint("TOPLEFT", 12, -66)

        local errs = PlaceCard(parent, L["CARD_ERRORS"], y - 114, 96)
        page.errorCount = Kit.Text(errs, 12)
        page.errorCount:SetPoint("TOPLEFT", 16, -44)
        local show = Kit.Button(errs, L["BTN_PRINT_ERRORS"], 130, function() NS:PrintErrors() end)
        show:SetPoint("TOPLEFT", 14, -62)
        local clear = Kit.Button(errs, L["BTN_CLEAR_ERRORS"], 130, function()
            NS:ClearErrors()
            page:refresh()
        end)
        clear:SetPoint("LEFT", show, "RIGHT", 10, 0)

        local blocked = PlaceCard(parent, L["CARD_BLOCKED"], y - 220, 70)
        page.blocked = Kit.Text(blocked, 12)
        page.blocked:SetPoint("TOPLEFT", 16, -44)
        page.blocked:SetPoint("RIGHT", blocked, "RIGHT", -16, 0)
    end,
    refresh = function(page)
        page.trace:SetChecked(NS.db.debug)
        page.cvars:SetChecked(NS.db.debugCVars)
        page.errorCount:SetText(string.format(L["ERRORS_COUNT"], #NS.db.errors))
        local b = NS.db.lastBlocked
        page.blocked:SetText(b and string.format("%s  %s: %s", b.time or "", b.event or "", b.func or "") or L["BLOCKED_NONE"])
    end,
})

---------------------------------------------------------------------------------------------------------------
-- About
---------------------------------------------------------------------------------------------------------------

NS:AddPage(area.key, {
    key = "about",
    title = L["PAGE_ABOUT"],
    build = function(_, parent)
        local y = Kit.PageHeader(parent, L["TITLE"] .. "  |cff8a8d91v" .. NS.version .. "|r", L["ABOUT_DESC"])
        local cmds = PlaceCard(parent, L["CARD_COMMANDS"], y, 200)
        local text = Kit.Paragraph(cmds, table.concat(NS.CommandHelp(), "\n"), 600, 12)
        text:SetPoint("TOPLEFT", 16, -42)
        local by = Kit.Text(parent, 11, C.muted)
        by:SetPoint("TOPLEFT", 0, y - 214)
        by:SetText(L["ABOUT_AUTHOR"])
    end,
})
