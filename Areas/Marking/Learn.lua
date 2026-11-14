local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Real mob names and marks inside dungeons (kb/addons/Bulwark.md, "Research: real mob names..."). Names and marks are
-- secret to addons there, but the chat client fills in "%t" itself: the target's name, prefixed with its raid mark as
-- {rtN}. On every hostile target change we whisper ourselves "%t" and read the echo, which is plain text outside boss
-- encounters [in-game 2026-11-14: out of combat and in trash combat; every addon send blocked during an encounter].
-- The whispers never show: a chat filter discards them, which also skips the whisper sound and the reply target.
-- A loophole Blizzard may close: everything falls back to the offline data names (rec.dataName).
local Learn = MK:RegisterModule("Learn")
local Utils = MK.Utils

local TAG = "BWK~"             -- sent "BWK~<n>~%t"; the echo reads "BWK~<n>~{rt4}Twilight Grunt"
local MIN_GAP = 0.25           -- seconds between whispers (a burst of Tab presses sends the last target only)
local PENDING_TTL = 10         -- an echo later than this is ignored

local seq, lastSend = 0, -math.huge
local retryQueued = false
local inEncounter = false
local markEpoch = 0            -- +1 on every mark change: worth asking the current target again
local pending = {}             -- [n] = { rec, epoch, at }

-- =========================================================================
-- Pure part (tests drive it directly)
-- =========================================================================

-- "BWK~12~{rt4}Twilight Grunt" -> 12, 4, "Twilight Grunt". icon 0 = unmarked. nil if it isn't ours. A name of ""
-- or "<no target>" (the target was gone when the client sent it) comes back as nil.
function Learn.Parse(text)
    if type(text) ~= "string" or Utils.IsSecret(text) then return nil end
    local n, rest = text:match("^BWK~(%d+)~(.*)$")
    if not n then return nil end
    local icon = 0
    local tag, after = rest:match("^{([^}]*)}(.*)$")
    if tag then
        local tags = ICON_TAG_LIST
        icon = tonumber(tag:match("^[rR][tT](%d)$")) or (type(tags) == "table" and tags[tag:lower()]) or 0
        rest = after
    end
    local name = strtrim(rest)
    if name == "" or name:sub(1, 1) == "<" then name = nil end
    return tonumber(n), icon, name
end

function Learn.IsOurs(text)
    return type(text) == "string" and not Utils.IsSecret(text) and text:find("^BWK~%d+~") ~= nil
end

-- The name a mob goes by in announcements: readable name (open world), learned name, unique offline data name.
function Learn.NameOf(rec)
    return rec.name or rec.learnedName or rec.dataName
end

-- =========================================================================
-- Who wears which icon. Two sources, the newest wins: icons our keys put on a plate (Planner.placed/placedAt, from
-- SetRaidTarget) and marks learned from the echo (anyone's, Learn.claims). A unit wears one icon, an icon sits on
-- one unit. Learned marks outlive later mark changes (marking the rest of the pack mustn't forget someone else's
-- skull) but are only used while still plausible: the icon is still in use and the mob's plate still shows an icon.
-- A swap between two marked mobs by someone else stays unseen until you target one of them again.
-- =========================================================================
Learn.claims = {}   -- [icon] = { rec = plate record, at = GetTime() } latest learned claim per icon

-- A mob was seen wearing `icon` (0 = none) at `at`: it no longer wears any other icon we thought it did.
function Learn.Claim(rec, icon, at)
    for i, c in pairs(Learn.claims) do
        if c.rec == rec then Learn.claims[i] = nil end
    end
    if icon and icon > 0 then Learn.claims[icon] = { rec = rec, at = at } end
end

-- Our key just put `icon` on `rec` (Planner's SetRaidTarget hook): older learned claims for either are void.
function Learn.Superseded(rec, icon)
    if rec then Learn.Claim(rec, 0) end
    if icon and icon > 0 then Learn.claims[icon] = nil end
end

-- The newest known wearer of an icon: rec (alive or dead), false (ours, on a unit without a plate) or nil; and
-- "ours" or "learned".
function Learn.Wearer(icon)
    local P = MK.Planner
    local placed, claim = P.placed[icon], Learn.claims[icon]
    if placed ~= nil and not (claim and claim.at > (P.placedAt[icon] or 0)) then return placed, "ours" end
    if claim then return claim.rec, "learned" end
    return nil
end

-- Whether some unit wears the icon (readable, [in-game] run 3). Unknown counts as in use (never rules one out).
local function IconInUse(icon)
    local ok, nextFree = pcall(GetNextAvailableRaidTargetMarkerIndex, icon, false, false, true)
    if not ok or Utils.IsSecret(nextFree) or type(nextFree) ~= "number" then return true end
    return nextFree ~= icon
end

-- The living mob wearing each icon: [icon] = rec. A mob claimed for two icons counts for its newest only.
function Learn.MobsByIcon()
    local Plates, P, list = MK.Plates, MK.Planner, {}
    for icon = 1, 8 do
        local rec, kind = Learn.Wearer(icon)
        if rec and not rec.dead and Plates.records[rec.token] == rec and Plates:IsMarked(rec.token)
            and IconInUse(icon) then
            local at = (kind == "ours") and (P.placedAt[icon] or 0) or Learn.claims[icon].at
            table.insert(list, { icon = icon, rec = rec, at = at })
        end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    local byIcon, used = {}, {}
    for _, c in ipairs(list) do
        if not used[c.rec] then byIcon[c.icon], used[c.rec] = c.rec, true end
    end
    return byIcon
end

-- =========================================================================
-- Shell
-- =========================================================================

-- Learning needs: the option on, no boss fight (sends are blocked and Blizzard shows an error), a hostile mob with a
-- plate whose name isn't readable anyway, and nothing learned for it since the last mark change.
local function Wanted(rec)
    if not rec or rec.player or not rec.hostile or rec.dead then return false end
    if rec.name then return false end   -- open world: the name is readable, no whisper needed
    return rec.learnedName == nil or rec.learnedEpoch ~= markEpoch
end

function Learn:Try()
    if not MK.isEnabled or not MK:Get("learnNames") or inEncounter or NS.Utils.ChatRestricted() then return end
    if not UnitExists("target") then return end
    local rec = MK.Plates:RecordFor("target")
    if not Wanted(rec) then return end
    local wait = lastSend + MIN_GAP - GetTime()
    if wait > 0 then
        if not retryQueued then
            retryQueued = true
            C_Timer.After(wait, function() retryQueued = false; Learn:Try() end)
        end
        return
    end
    local me = MK.Team.FullName("player")
    if not me then return end
    seq = seq + 1
    pending[seq] = { rec = rec, epoch = markEpoch, at = GetTime() }
    lastSend = GetTime()
    local ok, err = pcall(C_ChatInfo.SendChatMessage, TAG .. seq .. "~%t", "WHISPER", nil, me)
    if not ok then
        pending[seq] = nil
        MK:Debug("learn: send failed (%s)", tostring(err))
    end
end

local function OnEcho(text)
    local n, icon, name = Learn.Parse(text)
    local entry = n and pending[n]
    if not entry then return end
    pending[n] = nil
    local rec = entry.rec
    if GetTime() - entry.at > PENDING_TTL or MK.Plates.records[rec.token] ~= rec then return end   -- plate gone/reused
    if not name then return end
    rec.learnedName, rec.learnedIcon, rec.learnedEpoch = name, icon, entry.epoch
    Learn.Claim(rec, icon, entry.at)   -- the time it was asked: a mark change after that is newer
    MK:Debug("learn: %s = %s%s", rec.token, name, icon > 0 and (" (mark " .. icon .. ")") or "")
    MK:Fire("MOB_LEARNED", rec)
end

-- =========================================================================
-- Damage meter (kb/addons/Bulwark.md: [in-game] 2 s after a pull, EnemyDamageTaken lists one row per creature type
-- fought, with a plain name and creature ID, inside dungeons). It can't say which plate was which, so names from it
-- only go into the mob database: matched to the offline data by name, which gives the body (model) and power type,
-- hence the same signature a plate of that mob has.
-- =========================================================================
local POWER_TOKENS = { R = "RAGE", M = "MANA" }

-- The offline data rows for a name in an instance, one per body (model) it uses, by model ID (a stable order):
-- { { model, power token, boss, minimum level }, ... }. Empty if unknown.
function Learn.DataByName(instanceID, name)
    local mobs = instanceID and MK.InstanceMobs and MK.InstanceMobs[instanceID]
    local found = {}
    if not mobs or not MK.Rules.ParseVariant then return found end
    for model, variants in pairs(mobs) do
        for _, v in ipairs(variants) do
            local row = MK.Rules.ParseVariant(v)
            if row and row.name == name then
                table.insert(found, { model = model, power = POWER_TOKENS[row.p], boss = row.boss, level = row.lo })
                break
            end
        end
    end
    table.sort(found, function(a, b) return a.model < b.model end)
    return found
end

-- One meter row -> AdoptName arguments: the signatures of every body the name uses, the rules' priority, a level.
-- classification ("elite", "normal", ...) is readable; the data's boss flag wins.
function Learn.FromMeterRow(instanceID, name, classification)
    local rows = Learn.DataByName(instanceID, name)
    local first = rows[1]
    local tier = (first and first.boss) and "boss" or classification or "normal"
    local sigs = {}
    for _, d in ipairs(rows) do table.insert(sigs, MK.Rules.Signature(nil, tier, d.power, d.model)) end
    local prio = MK.Rules.RoleTierPrio(MK.Rules.RoleFromPower(first and first.power), tier)
    return sigs, prio, first and first.level
end

function Learn:ReadMeter()
    if not MK.isEnabled or not MK:Get("learnNames") or not MK.Plates.inInstance or InCombatLockdown() then return 0 end
    local meter, E = C_DamageMeter, Enum
    if not (meter and meter.GetCombatSessionFromType and E and E.DamageMeterSessionType and E.DamageMeterType) then return 0 end
    local ok, session = pcall(meter.GetCombatSessionFromType, E.DamageMeterSessionType.Current,
        E.DamageMeterType.EnemyDamageTaken)
    if not ok or Utils.IsSecret(session) or type(session) ~= "table" then return 0 end
    local sources = session.combatSources
    if Utils.IsSecret(sources) or type(sources) ~= "table" then return 0 end
    local added = 0
    for _, src in ipairs(sources) do
        local name = type(src) == "table" and not Utils.IsSecret(src) and src.name
        if type(name) == "string" and not Utils.IsSecret(name) and name ~= "" and src.isLocalPlayer ~= true then
            local class = src.classification
            if Utils.IsSecret(class) or type(class) ~= "string" then class = nil end
            local sigs, prio, level = Learn.FromMeterRow(MK.Plates.instanceID, name, class)
            if MK.MobDB:AdoptName(name, sigs, prio, level) then added = added + 1 end
        end
    end
    if added > 0 then MK:Debug("learn: %d name(s) from the damage meter", added) end
    return added
end

-- Hide our whispers in every chat frame (both the outgoing echo and the copy we receive).
local FILTER_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }
local function Filter(_, _, msg, ...)
    if Learn.IsOurs(msg) then return true end
    return false, msg, ...
end

local markRetry = false
local frame = CreateFrame("Frame", "BWK_LearnFrame")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        Learn:Try()
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        OnEcho((...))
    elseif event == "RAID_TARGET_UPDATE" then
        markEpoch = markEpoch + 1
        -- The current target may have just been marked: learn its mark once the burst of updates settles.
        if not markRetry then
            markRetry = true
            C_Timer.After(0.3, function() markRetry = false; Learn:Try() end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The meter's session is secret in combat; 2 s after it worked in-game.
        C_Timer.After(2, function() Learn:ReadMeter() end)
    elseif event == "ENCOUNTER_START" then
        inEncounter = true
    elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
        inEncounter = false
        if event == "PLAYER_ENTERING_WORLD" then wipe(pending) end
    end
end)

function Learn:OnEnable()
    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "CHAT_MSG_WHISPER_INFORM", "RAID_TARGET_UPDATE",
        "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        frame:RegisterEvent(ev)
    end
    local util = ChatFrameUtil
    if util and util.AddMessageEventFilter then
        for _, ev in ipairs(FILTER_EVENTS) do util.AddMessageEventFilter(ev, Filter) end
    end
end

function Learn:OnDisable()
    frame:UnregisterAllEvents()
    local util = ChatFrameUtil
    if util and util.RemoveMessageEventFilter then
        for _, ev in ipairs(FILTER_EVENTS) do util.RemoveMessageEventFilter(ev, Filter) end
    end
    wipe(pending)
end
