-- Per-character setups (ported from TankMarkForever tests/profile_test.lua): each character keeps its own team
-- setup; the mob database stays account-wide. (TankMark's one-off copy of an old account-wide setup isn't ported:
-- Bulwark never had one.)
local H = require("mark_helpers")

return function(_, t)
    -- A character that has its own setup keeps it.
    local own = t.fresh(function(s)
        H.install(s)
        s.env.BulwarkDB = { marking = { mobs = { ["Test Zone"] = { names = {}, sigs = {} } } } }
        s.env.BulwarkCharDB = { marking = { setup = { rows = {
            { icon = 1, role = "TANK" }, { icon = 2, role = "TANK" }, { icon = 3, role = "TANK" },
            { icon = 4, role = "CC", player = "Mine Friend" }, { icon = 5, role = "TANK" }, { icon = 6, role = "TANK" },
            { icon = 7, role = "TANK" }, { icon = 8, role = "TANK" },
        } } } }
    end)
    t.eq(own.env.BulwarkCharDB.marking.setup.rows[4].player, "Mine Friend", "own setup kept")
    t.eq(own.env.Bulwark.Marking.Team:Rows()[1].icon, 1, "the team uses the character's setup")
    t.ok(own.env.BulwarkDB.marking.mobs["Test Zone"], "mob database stays account-wide")

    -- Reset only resets this character's setup.
    own.env.Bulwark.Marking.Team:Reset()
    t.eq(own.env.BulwarkCharDB.marking.setup.rows[1].icon, 8, "reset to the default order")

    -- Fresh install: default setup per character, none account-wide.
    local fresh = t.fresh(function(s) H.install(s) end)
    t.eq(fresh.env.BulwarkDB.marking.setup, nil, "no account-wide setup")
    t.eq(#fresh.env.BulwarkCharDB.marking.setup.rows, 8, "default setup for the character")
end
