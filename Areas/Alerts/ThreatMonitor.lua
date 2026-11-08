local ADDON_NAME, NS = ...
local L, Utils = NS.L, NS.Utils

-- Threat whispers (from TankAlertForever Modules/ThreatMonitor.lua): in combat, once a second, whisper group
-- members whose threat on your target passes the threshold. Threat values can be secret in combat
-- (kb/restrictions.md); secret readings are skipped, so this may stay quiet in restricted fights [unverified].
local ThreatMonitor = NS:RegisterModule("ThreatMonitor", "alerts")
local frame = CreateFrame("Frame", "Bulwark_ThreatMonitorFrame")

local ticker = nil
local lastWhisper = {}

local function cfg() return NS.db.alerts end

local function Check()
    local c = cfg()
    if not c.announceThreatWhisper then return end
    if not UnitExists("target") or UnitIsDead("target") or UnitIsFriend("player", "target") then return end
    if c.onlyTankWhispers then
        local ok, tanking = pcall(UnitDetailedThreatSituation, "player", "target")
        if not ok or Utils.IsSecret(tanking) or not tanking then return end
    end

    local group = Utils.GetGroupType()
    if group == "SOLO" then return end
    local prefix = group == "RAID" and "raid" or "party"
    local count = group == "RAID" and GetNumGroupMembers() or GetNumSubgroupMembers()
    local mob = Utils.GetSafeUnitName("target", L["THE_TARGET"])
    local now = GetTime()
    for i = 1, count or 0 do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and not UnitIsDeadOrGhost(unit) then
            local ok, tanking, _, percent, rawPercent = pcall(UnitDetailedThreatSituation, unit, "target")
            -- Skip members tanking it themselves (co-tank taunt).
            if ok and (Utils.IsSecret(tanking) or not tanking) then
                local pct = Utils.SafeNumber(percent) or Utils.SafeNumber(rawPercent)
                if pct and pct >= c.threatWhisperThreshold then
                    local name = Utils.GetSafeUnitName(unit, nil)
                    if name and now - (lastWhisper[name] or 0) >= c.whisperThrottle then
                        lastWhisper[name] = now
                        NS.AlertsAnnouncer:Whisper(name, pct, mob)
                    end
                end
            end
        end
    end
end

local function Start()
    if ticker then ticker:Cancel() end
    wipe(lastWhisper)
    ticker = C_Timer.NewTicker(1, Check)
end

local function Stop()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    wipe(lastWhisper)
end

function ThreatMonitor:OnEnable()
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then Start() else Stop() end
    end)
    if InCombatLockdown() then Start() end
end

function ThreatMonitor:OnDisable()
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    Stop()
end

-- /bwk alerts test whisper [name]: whispers yourself (or name) a sample warning.
function ThreatMonitor:Simulate(name)
    local recipient = Utils.SafeString(name, nil) or Utils.GetSafeUnitName("player", "Player")
    NS:Print(L["TEST_WHISPER_TO"], recipient)
    NS.AlertsAnnouncer:Whisper(recipient, 95, Utils.GetSafeUnitName("target", L["TEST_DUMMY"]))
end
