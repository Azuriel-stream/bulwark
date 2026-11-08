local ADDON_NAME, NS = ...

-- Error recorder: the client doesn't write Lua errors to disk (kb/gotchas.md#menu-crash), so Bulwark keeps its own
-- in BulwarkDB.errors for review after a /reload or logout. Loaded first in the TOC so it also sees load-time errors.
-- Source: a post-hook on Blizzard's ScriptErrorsFrame, which receives every Lua error and warning with its stack
-- (Blizzard_ScriptErrorsFrame.lua AddLuaErrorHandler). A post-hook leaves Blizzard's error path untainted;
-- replacing the global error handler (seterrorhandler) would not.

local MAX_ERRORS = 30
local MAX_STACK = 2000
local MAX_LOCALS = 1500
local WARNING_TYPE = 1      -- ScriptErrorsFrame's message types: 0 = error, 1 = warning

local pending = {}          -- recorded before SavedVariables are loaded (ADDON_LOADED)
local busy = false

local function IsSecret(val)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, val)
        if ok then return secret == true end
    end
    return not pcall(function() return val .. "" end)
end

local function Text(val, limit)
    if val == nil then return nil end
    if IsSecret(val) then return "<secret>" end
    val = tostring(val)
    if #val > limit then val = val:sub(1, limit) .. "..." end
    return val
end

-- Ours if the message or the stack names our folder/frames ("Bulwark...") or one of our secure buttons ("BWK_").
local function IsOurs(msg, stack)
    for _, text in ipairs({ msg, stack }) do
        if text and (text:find(ADDON_NAME, 1, true) or text:find("BWK_", 1, true)) then return true end
    end
    return false
end

local function Store(list, entry)
    for _, old in ipairs(list) do
        if old.msg == entry.msg and old.stack == entry.stack then
            old.count = old.count + entry.count
            old.last = entry.last
            return false
        end
    end
    table.insert(list, entry)
    while #list > MAX_ERRORS do table.remove(list, 1) end
    return true
end

-- One chat line per new error; repeats only raise its count.
local function Notify(entry)
    if NS.Print and NS.L then
        NS:Print(NS.L["ERRORS_RECORDED"], (entry.msg:gsub("|", "||")))
    end
end

-- msg/stack/locals as the client hands them over; quiet = the caller already printed it.
function NS:RecordError(msg, stack, locals, quiet)
    if busy then return end
    busy = true
    pcall(function()
        msg, stack = Text(msg, MAX_STACK) or "?", Text(stack, MAX_STACK)
        if not IsOurs(msg, stack) then return end
        local now = date("%Y-%m-%d %H:%M:%S")
        local entry = {
            msg = msg, stack = stack, locals = Text(locals, MAX_LOCALS), count = 1, first = now, last = now,
            combat = InCombatLockdown() or nil, version = NS.version,
        }
        if not (NS.db and NS.db.errors) then
            Store(pending, entry)
        elseif Store(NS.db.errors, entry) and not quiet then
            Notify(entry)
        end
    end)
    busy = false
end

-- Called once the SavedVariables are in (ADDON_LOADED).
function NS:FlushErrors()
    for _, entry in ipairs(pending) do
        if Store(NS.db.errors, entry) then Notify(entry) end
    end
    wipe(pending)
end

-- Traceback for pcall'd module code: xpcall(fn, NS.Trap, ...) records the error with its stack, then hands it back.
function NS.Trap(err)
    NS:RecordError(err, debugstack and debugstack(2), nil, true)
    return err
end

if ScriptErrorsFrame and type(ScriptErrorsFrame.DisplayMessageInternal) == "function" then
    NS.errorHook = pcall(hooksecurefunc, ScriptErrorsFrame, "DisplayMessageInternal",
        function(_, message, messageType, stack, locals)
            if messageType == WARNING_TYPE then
                if IsSecret(message) then return end
                message = "Warning: " .. tostring(message)
            end
            NS:RecordError(message, stack, locals)
        end)
end
