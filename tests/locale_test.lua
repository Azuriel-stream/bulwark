-- Locale strings: a string used with string.format (it has %s, %d, %.2f ...) must write a literal percent as %%.
-- A bare "100% miss" or "1% = 12" throws "invalid conversion" at runtime (happened twice on 2026-11-12).
return function(sim, t)
    local L = sim.env.Bulwark.L
    local bad = {}
    for key, text in pairs(L) do
        if type(text) == "string" and text:find("%%[-+ #0]*%d*%.?%d*[sdifgxXcq]") then
            local ok, err = pcall(string.format, text, "x", "x", "x", "x", "x", "x")
            -- numbers for %d/%f are fed "x" and fail with "number expected": that's fine; anything else is a bad %.
            if not ok and not tostring(err):find("number expected", 1, true) then
                bad[#bad + 1] = key .. ": " .. tostring(err)
            end
            local stripped = text:gsub("%%%%", ""):gsub("%%[-+ #0]*%d*%.?%d*[sdifgxXcq]", "")
            if stripped:find("%", 1, true) then bad[#bad + 1] = key .. ": bare % in a format string" end
        end
    end
    table.sort(bad)
    t.eq(#bad, 0, "format strings with a bare %: " .. table.concat(bad, "; "))
end
