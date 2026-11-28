local ADDON_NAME, NS = ...
local L = NS.L
local Utils = NS.Utils

-- Field tests: in-game checks that can't be run on demand (a group, a boss, a healer drinking...). Off by default
-- (/bwk tests on). Each test waits for its situation, then either records what it saw by itself ("auto") or asks one
-- question in a small popup ("ask": Pass / Fail with a note / Later / Skip). Results go to BulwarkDB.fieldTests
-- (written at logout or /reload) for review with tools/field-tests.ps1. The tests themselves are in
-- Core/FieldTestList.lua and use the ids of kb/testing.md.
--
-- A test (FT:Define):
--   id, title, kind = "auto" | "ask"
--   when(data, st)       polled every TICK s, out of combat (inCombat = true: also in combat). true = the situation is here.
--   probe(data, st)      auto only, runs once `when` says yes: nil/false = not done yet, true = record "auto",
--                        or a status string ("pass" / "fail" / "auto").
--   events = { EVENT = function(data, st, ...) }   same return values as probe (ask: true = ready to ask).
--   onSaw(data, st, payload)   called by FT:Saw(id, payload) from feature code; same return values.
--                        Without onSaw, Saw merges the payload into data and the test is ready / recorded.
--   atLogin(data, st)    once at login.
--   question (string or function(data)), action = { label, fn }   ask only.
--   rev                  optional number: bump it when the test changes, so an old result doesn't count any more.
-- data is per session (may briefly hold secrets: Record turns them into "<secret>"); FT:Progress(id) persists.

local FT = NS:RegisterModule("FieldTests")

local TICK = 3
local LOGIN_DELAY = 15      -- no popup in the first seconds after login
local GAP = 20              -- between two popups
local SNOOZE = 900          -- "Later"
local MAX_DEPTH = 5
local MAX_STRING = 400
local WIDTH = 372

local defs, order = {}, {}
local live = {}             -- [id] = { data = {}, triggered = bool, snoozeUntil = t }
local ticker, popup, current
local lastPopup = -math.huge
local loginAt, loginStamp = 0, ""
local eventFrame = CreateFrame("Frame", "Bulwark_FieldTestEvents")

local function db() return NS.db.fieldTests end
function FT:IsOn() return NS.db ~= nil and db().on == true end

function FT:Define(def)
    assert(type(def.id) == "string" and (def.kind == "auto" or def.kind == "ask"), "field test needs an id and a kind")
    if not defs[def.id] then order[#order + 1] = def.id end
    defs[def.id] = def
end

local function State(id)
    live[id] = live[id] or { data = {} }
    return live[id]
end

local function Done(id)
    local r = db().results[id]
    -- A test whose definition got a new `rev` runs again (its old result is replaced when the new one comes in).
    return r ~= nil and r.status ~= nil and r.rev == defs[id].rev
end

function FT:Progress(id)
    db().progress[id] = db().progress[id] or {}
    return db().progress[id]
end

function FT.Now() return date("%Y-%m-%d %H:%M:%S") end

-- Bulwark errors recorded since stamp (same date format), optionally only those whose text contains `find`.
function FT.ErrorsSince(stamp, find)
    local out = {}
    for _, e in ipairs(NS.db.errors or {}) do
        local msg = tostring(e.msg)
        if (e.last or "") >= (stamp or "") and (not find or msg:find(find, 1, true)) then
            out[#out + 1] = msg:sub(1, 200)
            if #out >= 5 then break end
        end
    end
    return out
end

-- Copy for SavedVariables: secrets become "<secret>", functions etc. a type name, long strings are cut.
local function Clean(v, depth)
    if Utils.IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "table" then
        if depth >= MAX_DEPTH then return "<table>" end
        local out = {}
        for k, x in pairs(v) do
            if not Utils.IsSecret(k) and (type(k) == "string" or type(k) == "number") then
                out[k] = Clean(x, depth + 1)
            end
        end
        return out
    elseif t == "string" then
        return #v > MAX_STRING and v:sub(1, MAX_STRING) or v
    elseif t == "number" or t == "boolean" or t == "nil" then
        return v
    end
    return "<" .. t .. ">"
end
FT.Clean = Clean

local function Context()
    local ctx = {
        at = FT.Now(), version = NS.version, class = NS.playerClass, group = Utils.GetGroupType(),
        combat = InCombatLockdown() or nil,
    }
    local okL, level = pcall(UnitLevel, "player")
    ctx.level = okL and Clean(level, 0) or nil
    local okZ, zone = pcall(GetRealZoneText)
    ctx.zone = okZ and Clean(zone, 0) or nil
    local okI, inInstance, kind = pcall(IsInInstance)
    if okI and inInstance == true then ctx.instance = Clean(kind, 0) end
    local errors = FT.ErrorsSince(loginStamp)
    if #errors > 0 then ctx.errors = errors end
    return ctx
end

-- =========================================================================
-- Popup
-- =========================================================================

local function HidePopup()
    current = nil
    if popup then popup:Hide() end
end

function FT:Record(id, status, note)
    local def = defs[id]
    if not def or Done(id) then return end
    local st = State(id)
    db().results[id] = { status = status, note = note, title = def.title, data = Clean(st.data, 0), ctx = Context(),
                         rev = def.rev }
    db().progress[id] = nil
    if current == id then HidePopup() end
    NS:Print(L["FT_RECORDED"], def.title, L["FT_ST_" .. status] or status)
end

local function Question(id)
    local def, q = defs[id], defs[id].question
    if type(q) == "function" then
        local ok, text = pcall(q, State(id).data)
        q = ok and text or ("(question failed: " .. tostring(text) .. ")")
    end
    return tostring(q or "")
end

local function Height(fs, fallback)
    local h = tonumber(fs:GetStringHeight())
    return h and h > 0 and h or fallback
end

local function Layout()
    local h = 30 + Height(popup.title, 16) + 8 + Height(popup.question, 40) + 14
    if popup.action:IsShown() then h = h + 34 end
    if popup.noteMode then h = h + 32 end
    popup:SetHeight(h + 24 + 14)
end

local function SetNoteMode(on)
    popup.noteMode = on
    for _, b in ipairs(popup.answers) do b:SetShown(not on) end
    popup.note:SetShown(on)
    popup.save:SetShown(on)
    popup.back:SetShown(on)
    popup.note:SetText("")
    if on then popup.note:SetFocus() else popup.note:ClearFocus() end
    Layout()
end

local function Answer(status)
    local id = current
    if not id then return end
    if status == "later" then
        State(id).snoozeUntil = GetTime() + SNOOZE
        HidePopup()
    elseif status == "fail" then
        SetNoteMode(true)
    else
        FT:Record(id, status)
    end
end

local function SaveFail()
    local id = current
    if not id then return end
    local text = popup.note:GetText()
    FT:Record(id, "fail", (type(text) == "string" and text ~= "") and text or nil)
end

local function CreatePopup()
    local Kit = NS.Kit
    local C = Kit.C
    local f = CreateFrame("Frame", "Bulwark_FieldTest", UIParent)
    f:SetSize(WIDTH, 160)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Kit.Fill(f, C.bg)
    Kit.Border(f, C.goldDim)

    f.header = Kit.Text(f, 10, C.muted)
    f.header:SetPoint("TOPLEFT", 14, -10)
    f.header:SetText(L["FT_HEADER"])
    f.more = Kit.Text(f, 10, C.muted)
    f.more:SetPoint("TOPRIGHT", -14, -10)
    f.title = Kit.Text(f, 14, C.goldText)
    f.title:SetPoint("TOPLEFT", 14, -28)
    f.title:SetWidth(WIDTH - 28)
    f.question = Kit.Paragraph(f, "", WIDTH - 28, 12)
    f.question:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.action = Kit.Button(f, "", 160, function()
        local def = current and defs[current]
        if def and def.action then pcall(def.action.fn) end
    end)
    f.action:SetPoint("TOPLEFT", f.question, "BOTTOMLEFT", 0, -10)

    f.answers = {}
    for i, key in ipairs({ "pass", "fail", "later", "skip" }) do
        local b = Kit.Button(f, L["FT_" .. key:upper()], 80, function() Answer(key) end)
        b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 88, 14)
        f.answers[i] = b
    end

    f.note = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.note:SetSize(WIDTH - 40, 22)
    f.note:SetPoint("BOTTOMLEFT", 20, 46)
    f.note:SetAutoFocus(false)
    f.note:SetMaxLetters(240)
    f.note:SetScript("OnEnterPressed", SaveFail)
    f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.noteHint = Kit.Text(f.note, 10, C.muted)
    f.noteHint:SetPoint("BOTTOMLEFT", f.note, "TOPLEFT", -4, 2)
    f.noteHint:SetText(L["FT_NOTE_HINT"])
    f.save = Kit.Button(f, L["FT_SAVE"], 80, SaveFail)
    f.save:SetPoint("BOTTOMLEFT", 14, 14)
    f.back = Kit.Button(f, L["FT_BACK"], 80, function() SetNoteMode(false) end)
    f.back:SetPoint("BOTTOMLEFT", 102, 14)
    f:Hide()
    return f
end

local function ReadyToAsk(id, now)
    local def = defs[id]
    local st = live[id]
    return def.kind == "ask" and st and st.triggered and not Done(id) and (st.snoozeUntil or 0) <= now
end

local function Show(id)
    popup = popup or CreatePopup()
    current = id
    lastPopup = GetTime()
    local def = defs[id]
    popup.title:SetText(def.title)
    popup.question:SetText(Question(id))
    popup.action:SetShown(def.action ~= nil)
    if def.action then popup.action:SetLabel(def.action.label) end
    local others = 0
    for _, other in ipairs(order) do
        if other ~= id and ReadyToAsk(other, lastPopup) then others = others + 1 end
    end
    popup.more:SetText(others > 0 and string.format(L["FT_MORE"], others) or "")
    SetNoteMode(false)
    popup:Show()
end

-- =========================================================================
-- Situations
-- =========================================================================

local function Outcome(id, ok, res)
    if not ok then
        FT:Record(id, "broken", tostring(res))
        return
    end
    if not res then return end
    if defs[id].kind == "ask" then
        State(id).triggered = true
    else
        FT:Record(id, res == true and "auto" or tostring(res))
    end
end

-- Feature code reports what it just saw (cheap no-op while field tests are off or the test is done).
function FT:Saw(id, payload)
    if not FT:IsOn() then return end
    local def = defs[id]
    if not def or Done(id) then return end
    local st = State(id)
    if def.onSaw then
        Outcome(id, pcall(def.onSaw, st.data, st, payload))
    else
        if type(payload) == "table" then
            for k, v in pairs(payload) do st.data[k] = v end
        end
        Outcome(id, true, true)
    end
end

local function Tick()
    if not FT:IsOn() then return end
    local combat = InCombatLockdown()
    for _, id in ipairs(order) do
        local def = defs[id]
        if def.when and not Done(id) and (not combat or def.inCombat) then
            local st = State(id)
            if not (def.kind == "ask" and st.triggered) then
                local ok, res = pcall(def.when, st.data, st)
                if ok and res and def.kind == "auto" and def.probe then
                    ok, res = pcall(def.probe, st.data, st)
                end
                Outcome(id, ok, res)
            end
        end
    end
    local now = GetTime()
    if combat or current or now - lastPopup < GAP or now - loginAt < LOGIN_DELAY then return end
    for _, id in ipairs(order) do
        if ReadyToAsk(id, now) then
            Show(id)
            return
        end
    end
end
FT.Tick = Tick   -- tests

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" and current then HidePopup() end   -- asked again after the fight
    for _, id in ipairs(order) do
        local handler = defs[id].events and defs[id].events[event]
        if handler and not Done(id) then
            local st = State(id)
            Outcome(id, pcall(handler, st.data, st, ...))
        end
    end
end)

local function Start()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, Tick)
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_REGEN_DISABLED")
    for _, id in ipairs(order) do
        for event in pairs(defs[id].events or {}) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
    end
end

local function Stop()
    if ticker then ticker:Cancel() end
    ticker = nil
    eventFrame:UnregisterAllEvents()
    HidePopup()
end

function FT:SetOn(on)
    db().on = on and true or false
    if on then Start() else Stop() end
end

function FT:OnEnable()
    loginAt, loginStamp = GetTime(), FT.Now()
    for _, id in ipairs(order) do
        local def = defs[id]
        if def.atLogin and not Done(id) then
            local st = State(id)
            Outcome(id, pcall(def.atLogin, st.data, st))
        end
    end
    if FT:IsOn() then Start() end
end

-- =========================================================================
-- /bwk tests [on|off|list|ask <id>|reset <id>|all]
-- =========================================================================

local function Counts()
    local done, ready, waiting = 0, 0, 0
    local now = GetTime()
    for _, id in ipairs(order) do
        if Done(id) then done = done + 1
        elseif ReadyToAsk(id, now) then ready = ready + 1
        else waiting = waiting + 1 end
    end
    return done, ready, waiting
end

function FT:Command(rest)
    local a, b = (rest or ""):match("^(%S*)%s*(.-)$")
    a = (a or ""):lower()
    if a == "on" or a == "off" then
        FT:SetOn(a == "on")
        NS:Print(a == "on" and L["FT_ON"] or L["FT_OFF"])
    elseif a == "list" then
        for _, id in ipairs(order) do
            local r = db().results[id]
            local st = live[id]
            local status = r and (L["FT_ST_" .. r.status] or r.status)
                or (st and st.triggered and L["FT_ST_ready"]) or L["FT_ST_waiting"]
            print(string.format("  |cffffd160%s|r  %s  (%s)", id, defs[id].title, status))
        end
    elseif a == "ask" and b ~= "" then
        if not defs[b] then NS:Print(L["FT_UNKNOWN"], b)
        elseif defs[b].kind ~= "ask" then NS:Print(L["FT_NOT_ASK"], b)
        elseif Done(b) then NS:Print(L["FT_ALREADY"], b)
        elseif InCombatLockdown() then NS:Print(L["FT_COMBAT"])
        else State(b).triggered = true; Show(b) end
    elseif a == "reset" and b ~= "" then
        if b == "all" then
            wipe(db().results); wipe(db().progress); wipe(live)
            NS:Print(L["FT_RESET_ALL"])
        elseif defs[b] or db().results[b] then
            db().results[b], db().progress[b], live[b] = nil, nil, nil
            NS:Print(L["FT_RESET"], b)
        else
            NS:Print(L["FT_UNKNOWN"], b)
        end
    else
        local done, ready, waiting = Counts()
        NS:Print(L["FT_STATUS"], FT:IsOn() and L["STATUS_ON"] or L["STATUS_OFF"], done, #order, ready, waiting)
        print("  " .. L["HELP_TESTS"])
    end
end

function FT:GetPopup() return popup, current end   -- tests
