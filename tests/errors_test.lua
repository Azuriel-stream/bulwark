-- Error recorder (Core/Errors.lua, from TankMarkForever): Bulwark's own Lua errors (from Blizzard's error frame, caught module errors and blocked actions)
-- are kept in SavedVariables with their stack, de-duplicated with a count; other addons' errors are ignored.
local function count(list, pattern)
    local n = 0
    for _, line in ipairs(list) do if line:find(pattern, 1, true) then n = n + 1 end end
    return n
end

local OURS = "Interface/AddOns/Bulwark/Areas/Marking/Planner.lua:12: attempt to index a nil value"
local OUR_STACK = "[string \"@Interface/AddOns/Bulwark/Areas/Marking/Planner.lua\"]:12: in function <...>"

return function(_, t)
    local sim = t.fresh(function(s)
        s.env.ScriptErrorsFrame = { DisplayMessageInternal = function() end }
    end)
    local NS = sim.env.Bulwark
    local frame = sim.env.ScriptErrorsFrame
    t.ok(NS.errorHook, "hooked the error frame")
    local errors = NS.db.errors
    t.eq(#errors, 0, "starts empty")

    -- Ours: recorded with stack, locals and time; one chat line.
    frame:DisplayMessageInternal(OURS, 0, OUR_STACK, "self = <table>")
    t.eq(#errors, 1, "our error recorded")
    t.eq(errors[1].msg, OURS, "message kept")
    t.eq(errors[1].stack, OUR_STACK, "stack kept")
    t.eq(errors[1].locals, "self = <table>", "locals kept")
    t.eq(errors[1].count, 1, "count 1")
    t.ok(errors[1].first:match("^%d+%-%d+%-%d+ %d+:%d+:%d+$"), "dated: " .. tostring(errors[1].first))
    t.eq(count(sim.output, "Error recorded"), 1, "one chat notice")

    -- The same error again: count only, no new chat line.
    frame:DisplayMessageInternal(OURS, 0, OUR_STACK, "self = <table>")
    t.eq(#errors, 1, "repeat not duplicated")
    t.eq(errors[1].count, 2, "repeat counted")
    t.eq(count(sim.output, "Error recorded"), 1, "no second notice")

    -- Another addon's error: ignored. Ours found by the stack only: recorded.
    frame:DisplayMessageInternal("Interface/AddOns/Other/x.lua:1: nope", 0, "[string \"@Interface/AddOns/Other/x.lua\"]:1")
    t.eq(#errors, 1, "other addons ignored")
    frame:DisplayMessageInternal("attempt to compare a secret value", 0, OUR_STACK)
    t.eq(#errors, 2, "ours by stack")

    -- Warnings are tagged; a secret message is stored as <secret>.
    frame:DisplayMessageInternal("Bulwark: deprecated call", 1)
    t.eq(errors[3].msg, "Warning: Bulwark: deprecated call", "warning tagged")
    frame:DisplayMessageInternal(sim:maybeSecret("hidden", true), 0, OUR_STACK)
    t.eq(errors[4].msg, "<secret>", "secret message not stored")

    -- A module handler error Bulwark catches itself: recorded with its stack, printed once (by Fire).
    NS:On("TEST_BOOM", function() error("kaboom") end)
    local before = #sim.output
    NS:Fire("TEST_BOOM")
    local e = errors[#errors]
    t.ok(e.msg:find("kaboom", 1, true), "Fire error recorded")
    t.ok(e.stack and e.stack:find("Init.lua", 1, true), "with the stack through Fire")
    t.eq(#sim.output - before, 1, "one chat line (the Fire message)")

    -- Blocked actions are recorded too.
    sim:Fire("ADDON_ACTION_BLOCKED", "Bulwark", "SetRaidTarget")
    t.ok(errors[#errors].msg:find("ADDON_ACTION_BLOCKED: SetRaidTarget", 1, true), "blocked action recorded")
    sim:Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpell")
    t.ok(not errors[#errors].msg:find("CastSpell", 1, true), "other addons' blocks ignored")

    -- Capped at 30, oldest dropped.
    for i = 1, 40 do frame:DisplayMessageInternal("Bulwark err " .. i, 0, OUR_STACK) end
    t.eq(#errors, 30, "capped")
    t.eq(errors[30].msg, "Bulwark err 40", "newest kept")

    -- Errors before SavedVariables load are kept and flushed with a notice.
    local db = NS.db
    NS.db = nil
    frame:DisplayMessageInternal("Bulwark early", 0, OUR_STACK)
    NS.db = db
    NS:FlushErrors()
    t.eq(errors[30].msg, "Bulwark early", "pending error flushed")
    t.eq(count(sim.output, "Bulwark early"), 1, "flush notice")

    -- /bwk errors lists them; /bwk errors clear empties the list.
    sim:Slash("/bwk errors")
    t.eq(count(sim.output, "30 recorded error(s)"), 1, "list header")
    sim:Slash("/bwk errors clear")
    t.eq(#NS.db.errors, 0, "cleared")
    sim:Slash("/bwk errors")
    t.eq(count(sim.output, "No errors recorded."), 1, "empty list")

    -- No error frame (it failed to load): nothing breaks, the command says so.
    local sim2 = t.fresh(function(s) s.env.ScriptErrorsFrame = nil end)
    t.ok(not sim2.env.Bulwark.errorHook, "no hook without the frame")
    sim2:Slash("/bwk errors")
    t.eq(count(sim2.output, "could not be installed"), 1, "says so")
end
