local ADDON_NAME, NS = ...
local L, Utils = NS.L, NS.Utils

-- Sends the Alerts messages: channel choice, throttles, message text, threat whispers, chat colouring.
-- (from TankAlertForever Modules/Announcer.lua)
local Announcer = NS:RegisterModule("AlertsAnnouncer", "alerts")
NS.AlertsAnnouncer = Announcer

local lastCC, lastDisarm = 0, 0
local lastAbility = {}

local function cfg() return NS.db.alerts end

-- Output channel from the setting and the group: Auto = Raid Warning when leading/assisting a raid, else
-- Raid, Party, or Say when solo. A forced channel falls back when it isn't available.
function Announcer:GetChannel()
    local forced = Utils.SafeString(cfg().forceChannel, "auto"):lower()
    local group = Utils.GetGroupType()
    local lead = Utils.IsRaidLeaderOrAssist()
    if forced == "auto" or forced == "raid_warning" then
        if group == "RAID" then return lead and "RAID_WARNING" or "RAID" end
        if group == "PARTY" then return "PARTY" end
        return "SAY"
    elseif forced == "raid" then
        if group == "RAID" then return "RAID" end
        if group == "PARTY" then return "PARTY" end
        return "SAY"
    elseif forced == "party" then
        if group ~= "SOLO" then return "PARTY" end
        return "SAY"
    end
    return "SAY"
end

-- Local echo of an alert: raid icons as textures, failure words in red, arrows in gold.
local FAIL_WORDS = { "DODGED", "PARRIED", "MISSED", "RESISTED", "BLOCKED", "IMMUNE", "DEFLECTED", "REFLECTED", "EVADED" }
local function Colorize(msg)
    if not (msg:find("^>> ") and msg:find("<<")) then return msg end
    for _, word in ipairs(FAIL_WORDS) do
        msg = msg:gsub(word, "|cffFF2222" .. word .. "|r")
    end
    msg = msg:gsub("^>> ", "|cffFFD700>> |r"):gsub(" <<", " |cffFFD700<<|r")
    msg = msg:gsub("%(Watch threat%)", "|cffFF9900(Watch threat)|r")
    return msg
end

function Announcer:PrintLocal(msg)
    NS:Print(Colorize(Utils.ReplaceRaidTokens(msg)))
end

-- Sends to the channel. SAY/YELL in combat need a hardware event, Say solo would only talk to strangers, and while
-- the game restricts addon chat nothing can be sent: all three become a local line instead.
function Announcer:Send(msg, channel)
    msg = Utils.SafeString(msg, "")
    if msg == "" then return end
    channel = channel or self:GetChannel()
    if channel == "RAID_WARNING" and not Utils.IsRaidLeaderOrAssist() then
        channel = Utils.GetGroupType() == "RAID" and "RAID" or "PARTY"
    end
    local solo = Utils.GetGroupType() == "SOLO"
    if ((channel == "SAY" or channel == "YELL") and InCombatLockdown()) or (solo and channel == "SAY") then
        self:PrintLocal(msg)
        return
    end
    if Utils.ChatRestricted() then
        NS:Debug("chat restricted: %s shown locally instead of %s", msg, channel)
        self:PrintLocal(msg)
        return
    end
    if not pcall(C_ChatInfo.SendChatMessage, msg, channel) then
        self:PrintLocal(msg)
    end
end

local function TargetText(name, icon)
    name, icon = Utils.SafeString(name, ""), Utils.SafeString(icon, "")
    if name == "" then return "" end
    return icon ~= "" and (icon .. " " .. name) or name
end

-- Spell name as plain "[Name]", never a spell link: a ranked link corrupts the rest of a sent chat message on
-- Forever [in-game] (kb/gotchas.md#spell-link-chat).
local function SpellText(name)
    name = Utils.SafeString(name, "Ability")
    if name:sub(1, 1) == "[" and name:sub(-1) == "]" then return name end
    return "[" .. name .. "]"
end

local function PlayerName()
    return Utils.GetSafeUnitName("player", "Tank")
end

-- ">> [Taunt] RESISTED on {rt8} Defias Pillager! << (Watch threat)"; in Raid Warning it names the tank.
function Announcer:AbilityAlert(ability, failure, target, icon)
    if not NS:IsAreaRunning("alerts") then return end
    ability = Utils.SafeString(ability, "Ability")
    local now = GetTime()
    if now - (lastAbility[ability] or 0) < 1 then return end   -- duplicate events for one cast
    lastAbility[ability] = now

    local channel = self:GetChannel()
    local where = TargetText(target, icon)
    failure = Utils.SafeString(failure, "FAILED")
    local failText = L[failure]
    local spell = SpellText(ability)
    local msg
    if channel == "RAID_WARNING" then
        msg = where ~= "" and string.format(L["ALERT_ABILITY_RW"], PlayerName(), spell, failText, where)
            or string.format(L["ALERT_ABILITY_RW_NOTARGET"], PlayerName(), spell, failText)
    else
        msg = where ~= "" and string.format(L["ALERT_ABILITY"], spell, failText, where)
            or string.format(L["ALERT_ABILITY_NOTARGET"], spell, failText)
    end
    self:Send(msg, channel)
end

-- Stunned / feared / incapacitated, throttled by the alert throttle.
function Announcer:LossOfControlAlert(locType, target, icon)
    if not NS:IsAreaRunning("alerts") or not cfg().announceCC then return end
    local now = GetTime()
    if now - lastCC < (cfg().alertThrottle or 8) then return end
    lastCC = now
    local channel = self:GetChannel()
    local where = TargetText(target, icon)
    local what = L[Utils.SafeString(locType, "STUNNED")]
    local msg
    if channel == "RAID_WARNING" then
        msg = where ~= "" and string.format(L["ALERT_CC_RW"], PlayerName(), what, where)
            or string.format(L["ALERT_CC_RW_NOTARGET"], PlayerName(), what)
    else
        msg = string.format(L["ALERT_CC"], what)
    end
    self:Send(msg, channel)
end

function Announcer:DisarmAlert(target, icon)
    if not NS:IsAreaRunning("alerts") or not cfg().announceDisarm then return end
    local now = GetTime()
    if now - lastDisarm < (cfg().alertThrottle or 8) then return end
    lastDisarm = now
    local channel = self:GetChannel()
    local where = TargetText(target, icon)
    local msg
    if channel == "RAID_WARNING" then
        msg = where ~= "" and string.format(L["ALERT_DISARM_RW"], PlayerName(), where)
            or string.format(L["ALERT_DISARM_RW_NOTARGET"], PlayerName())
    else
        msg = L["ALERT_DISARM"]
    end
    self:Send(msg, channel)
end

-- "[Bulwark] Careful! You are at 95% threat on Defias Pillager!"
function Announcer:Whisper(recipient, percent, mob)
    recipient = Utils.SafeString(recipient, "")
    if recipient == "" then return end
    local msg = string.format(L["ALERT_THREAT_WHISPER"], math.floor(Utils.SafeNumber(percent, 0)),
        Utils.SafeString(mob, L["THE_TARGET"]))
    if Utils.ChatRestricted() then
        NS:Debug("chat restricted: whisper to %s not sent", recipient)
        return
    end
    pcall(C_ChatInfo.SendChatMessage, msg, "WHISPER", nil, recipient)
end

-- Colours alert lines (ours and other tanks') in the chat frame while Alerts runs.
local CHAT_EVENTS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }
local function ChatFilter(_, _, msg, ...)
    if type(msg) == "string" and not Utils.IsSecret(msg) then
        return false, Colorize(msg), ...
    end
    return false, msg, ...
end

function Announcer:OnEnable()
    local util = ChatFrameUtil
    if util and util.AddMessageEventFilter then
        for _, event in ipairs(CHAT_EVENTS) do util.AddMessageEventFilter(event, ChatFilter) end
    end
end

function Announcer:OnDisable()
    local util = ChatFrameUtil
    if util and util.RemoveMessageEventFilter then
        for _, event in ipairs(CHAT_EVENTS) do util.RemoveMessageEventFilter(event, ChatFilter) end
    end
    lastCC, lastDisarm = 0, 0
    wipe(lastAbility)
end
