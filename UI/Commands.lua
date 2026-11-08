local ADDON_NAME, NS = ...
local L = NS.L

-- Slash commands: /bulwark and /bwk only (no aliases of the old addons' commands, by design).
-- "/bwk <area> <args>" goes to the area's command handler once that area is ported.
local Commands = NS:RegisterModule("Commands")

local AREA_ALIASES = { mark = "marking", alert = "alerts" }

function NS.CommandHelp()
    local lines = {
        "|cffffd160/bwk|r  " .. L["HELP_TOGGLE"],
        "|cffffd160/bwk alerts|r, |cffffd160audit|r, |cffffd160mark|r  " .. L["HELP_AREA"],
        "|cffffd160/bwk settings|r  " .. L["HELP_SETTINGS"],
        "|cffffd160/bwk status|r  " .. L["HELP_STATUS"],
        "|cffffd160/bwk minimap|r  " .. L["HELP_MINIMAP"],
        "|cffffd160/bwk reset|r  " .. L["HELP_RESET"],
        "|cffffd160/bwk debug|r [on||off||cvars on||off]  " .. L["HELP_DEBUG"],
        "|cffffd160/bwk errors|r [clear]  " .. L["HELP_ERRORS"],
    }
    for _, area in ipairs(NS.areas) do
        for _, line in ipairs(area.commandHelp or {}) do table.insert(lines, line) end
    end
    return lines
end

function NS:PrintErrors()
    local list = NS.db.errors
    if #list == 0 then
        NS:Print(L["ERRORS_NONE"])
    else
        NS:Print(L["ERRORS_HEADER"], #list)
        for i, e in ipairs(list) do
            print(string.format("  %d. [%s x%d%s] %s", i, e.last or "?", e.count or 1, e.combat and ", combat" or "",
                (tostring(e.msg):gsub("|", "||"))))
        end
    end
    if not NS.errorHook then NS:Print(L["ERRORS_NO_HOOK"]) end
end

function NS:ClearErrors()
    wipe(NS.db.errors)
    NS:Print(L["ERRORS_CLEARED"])
end

local function PrintStatus()
    NS:Print(L["STATUS_HEADER"], NS.version)
    for _, area in ipairs(NS.areas) do
        if area.switch then
            local status = NS:AreaStatus(area.key)
            local text = status == "on" and L["STATUS_ON"] or status == "off" and L["STATUS_OFF"]
                or string.format(L["STATUS_WAITING_FOR"], NS:AreaBlockedBy(area.key) or "?")
            print(string.format("  %s: %s", area.title, text))
        end
    end
    print(string.format("  " .. L["STATUS_WINDOW"], (NS.db.ui.scale or 1) * 100,
        NS.db.minimap.hide and L["STATUS_OFF"] or L["STATUS_ON"]))
end

local function Debug(args)
    local a, b = args:match("^(%S*)%s*(%S*)")
    if a == "on" or a == "off" then
        NS.db.debug = (a == "on")
        NS:Print(NS.db.debug and L["DEBUG_ON"] or L["DEBUG_OFF"])
    elseif a == "cvars" and (b == "on" or b == "off") then
        NS:SetDebugCVars(b == "on")
        NS:Print(b == "on" and L["DEBUG_CVARS_ON"] or L["DEBUG_CVARS_OFF"])
    else
        NS:Print(L["DEBUG_STATE"], NS.db.debug and L["STATUS_ON"] or L["STATUS_OFF"],
            NS.db.debugCVars and L["STATUS_ON"] or L["STATUS_OFF"])
        local blocked = NS.db.lastBlocked
        if blocked then
            NS:Print(L["DEBUG_LAST_BLOCKED"], blocked.time or "?", blocked.event or "?", blocked.func or "?")
            print(blocked.stack or "")
        else
            NS:Print(L["BLOCKED_NONE"])
        end
    end
end

local function Handle(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local areaKey = AREA_ALIASES[cmd] or cmd
    local area = NS:GetArea(areaKey)

    if cmd == "" then
        NS.Window:Toggle()
    elseif area then
        if rest == "" then
            NS.Window:Open(area.key)
        elseif area.command then
            area.command(rest)
        else
            NS:Print(L["AREA_NO_COMMANDS"], area.title)
        end
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "minimap" then
        NS.MinimapButton:SetEnabled(not NS.MinimapButton:IsEnabled())
        NS:Print(NS.MinimapButton:IsEnabled() and L["MINIMAP_SHOWN"] or L["MINIMAP_HIDDEN"])
    elseif cmd == "reset" then
        NS.Window:SetScale(1)
        NS.Window:ResetPosition()
        NS:Print(L["WINDOW_RESET"])
    elseif cmd == "debug" then
        Debug(rest)
    elseif cmd == "errors" then
        if rest == "clear" then NS:ClearErrors() else NS:PrintErrors() end
    else
        NS:Print(L["HELP_HEADER"])
        for _, line in ipairs(NS.CommandHelp()) do print("  " .. line) end
    end
end

SLASH_BULWARK1 = "/bulwark"
SLASH_BULWARK2 = "/bwk"
SlashCmdList["BULWARK"] = Handle
Commands.Handle = Handle
