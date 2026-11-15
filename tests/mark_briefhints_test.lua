-- Briefing step 6 (kb/addons/Bulwark-Briefing.md): curated hints, generated into Data/MobAbilities.lua as
-- MK.BriefingHints[map][mob][spellID or "@mechanic"] = { flags, note } from tools/data/briefing-hints.json.
local H = require("mark_helpers")
local RFC, ROL = 389, 2999

local function setup(s)
    H.install(s)
    s.zone = "Ruins of Lordaeron"
    s.env.IsInInstance = function() return true, "party" end
    s.env.GetInstanceInfo = function() return "Ruins of Lordaeron", "party", 1, "Normal", 5, 0, false, ROL, 5, nil, false end
    s.known[72] = true
    s.equipped[17] = "|cffffffff|Hitem:4975::::::::|h[Vigilant Buckler]|h|r"
    s.itemInfo[4975] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
    s.spells[72], s.spells[20800], s.spells[18267] = "Shield Bash", "Immolate", "Curse of Weakness"
    s.spells[17307], s.spells[5568] = "Knockout", "Trample"
end

return function(_, t)
    local sim = t.fresh(setup)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local B, A = MK.Briefing, MK.Abilities
    local hints = MK.BriefingHints

    -- Generated table: shape, and every hinted spell is among its mob's casts (the generator adds missing ones).
    t.ok(type(hints) == "table" and hints[RFC] and hints[ROL], "hints generated for RFC and Ruins of Lordaeron")
    t.eq(hints[RFC]["Jergosh the Invoker"][20800].flags[1], "interrupt", "Jergosh: Immolate interrupt")
    for map, mobs in pairs(hints) do
        for mob, byKey in pairs(mobs) do
            local entry = B.FindEntry(mob, map)
            t.ok(entry ~= nil, "hinted mob has an entry: " .. mob)
            for key, h in pairs(byKey) do
                t.ok(type(h.flags) == "table" and #h.flags > 0, "flags for " .. mob .. " " .. tostring(key))
                local found = false
                for _, s in ipairs(B.EntrySpells(entry)) do if s.id == key then found = true end end
                t.ok(found, "hinted cast listed for " .. mob .. ": " .. tostring(key))
            end
        end
    end

    -- Mechanics: The Baron (no spell behind "Patrol" / "Hurl") show and post as notes.
    local baron = B.FindEntry("The Baron", ROL)
    t.eq(table.concat(baron.mechanics, ","), "@Hurl,@Patrol", "mechanics from the hints")
    local list = B.MobSpells(baron, function(id) return hints[ROL]["The Baron"][id] end)
    local patrol
    for _, item in ipairs(list) do if item.spell.id == "@Patrol" then patrol = item end end
    t.ok(patrol and patrol.prio == "info" and patrol.source == "hint", "Patrol: info from the hint")
    t.eq(A.Describe(patrol.spell), "Patrol: a mechanic to know (curated hint)", "mechanic description")
    t.eq(B.SpellName("@Patrol"), "Patrol", "mechanic name")

    -- In view: The Baron's notes are posted.
    sim.units.nameplate1 = { name = "The Baron", friendly = false, level = 30, tier = "elite", power = "RAGE" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    sim:Advance(1)
    local lines = B.BuildLines((B.Plan()))
    t.contains(lines, "Note: Hurl %(The Baron%): Throws the tank%. Aggro resets%.; Patrol %(The Baron%): Patrols: watch his path",
        "mechanic notes posted")
    -- Your override silences a mechanic.
    B.SetOverride("The Baron", "@Patrol", "ignore")
    lines = B.BuildLines((B.Plan()))
    t.eq(table.concat(lines, "\n"):find("Patrol", 1, true), nil, "ignored mechanic not posted")
    t.contains(lines, "Hurl %(The Baron%)", "the other one still is")
    B.SetOverride("The Baron", "@Patrol", nil)

    -- Jergosh alone (RFC): the hint makes Immolate a must the tank takes; the curse note follows.
    local jergosh = B.FindEntry("Jergosh the Invoker", RFC)
    local mobs = { { name = "Jergosh the Invoker", count = 1, boss = true,
                     spells = B.MobSpells(jergosh, function(id) return hints[RFC]["Jergosh the Invoker"][id] end) } }
    B.Assign(mobs, { { short = "Tankard", tank = true, kit = B.KitFor("WARRIOR", 20, { known = function(ids) return ids[1] == 72 end, shield = true }) } })
    lines = B.BuildLines(mobs)
    t.eq(lines[1], "[Bulwark] Interrupt: Jergosh the Invoker: Immolate -> Tankard (Shield Bash)", "hinted must")
    t.eq(lines[2], "[Bulwark] Note: Curse of Weakness (Jergosh the Invoker): Curse on the tank: remove it.", "hint note")

    -- Page: mechanic rows with the hint's note as the grey placeholder.
    local rows = B.AbilityRows(ROL)
    local row
    for _, r in ipairs(rows) do if r.spell and r.spell.id == "@Patrol" then row = r end end
    t.ok(row and row.auto == "info" and row.autoSource == "hint" and row.hintNote:find("^Patrols"), "Patrol row on the page")
    local page = H.page(sim, "briefing")
    page.instance = ROL
    page:refresh()
    local shown
    for _ = 1, 10 do
        for _, r in ipairs(page.rows) do
            if r:IsShown() and r.spellBtn:IsShown() and r.spell:GetText() == "Patrol" then shown = r end
        end
        if shown then break end
        page.nextPage:Click()
    end
    t.ok(shown, "Patrol listed on the page")
    t.contains({ shown.note.placeholder:GetText() }, "^hint: Patrols", "hint note shown in grey")
    t.eq(#sim.errors, 0, "no Lua errors")
end
