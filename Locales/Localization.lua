local ADDON_NAME, NS = ...

-- Missing keys fall back to the key itself, so a forgotten string shows up as its key instead of an error.
NS.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

local currentLocale = GetLocale and GetLocale() or "enUS"

-- Locale files call this; it returns the table to fill, or nil when that locale isn't the client's.
function NS:NewLocale(locale)
    if locale == "enUS" or locale == currentLocale then
        return NS.L
    end
    return nil
end
