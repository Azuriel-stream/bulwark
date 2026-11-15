-- Briefing step 3 (kb/addons/Bulwark-Briefing.md): the tile and the "Post briefing" key.
-- Shown out of combat, outside encounters and the Chat restriction, in an instance, in a group (or /bwk mark brief
-- test), with the option on, when a mob in view has a must cast or a boss is in view; hidden after a post until the
-- briefing changes. Edit Mode shows a sample to place it.
local H = require("mark_helpers")
local RFC = 389

local function InstallEditMode(s)
    local env = s.env
    local callbacks = {}
    env.EventRegistry = {
        RegisterCallback = function(_, event, fn, owner)
            callbacks[event] = callbacks[event] or {}
            table.insert(callbacks[event], { fn, owner })
        end,
        TriggerEvent = function(_, event, ...)
            for _, c in ipairs(callbacks[event] or {}) do c[1](c[2], ...) end
        end,
    }
    local f = s:CreateFrame("Frame", "EditModeManagerFrame", nil)
    f:Hide()
    f.editModeActive = false
    function f:IsEditModeActive() return self.editModeActive end
    function f:TestEnter()
        self:Show(); self.editModeActive = true
        env.EventRegistry:TriggerEvent("EditMode.Enter")
    end
    function f:TestExit()
        self.editModeActive = false; self:Hide()
        env.EventRegistry:TriggerEvent("EditMode.Exit")
    end
end

local function setup(s)
    InstallEditMode(s)
    H.install(s)
    s.zone = "Ragefire Chasm"
    s.env.IsInInstance = function() return true, "party" end
    s.env.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, RFC, 5, nil, false end
    s.known[72] = true   -- Shield Bash, shield worn
    s.equipped[17] = "|cffffffff|Hitem:4975::::::::|h[Vigilant Buckler]|h|r"
    s.itemInfo[4975] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
    s.spells[11986], s.spells[9532], s.spells[72], s.spells[20800] = "Healing Wave", "Lightning Bolt", "Shield Bash", "Immolate"
end

local function partyLines(sim)
    local n = 0
    for _, c in ipairs(sim.chat) do if c.channel == "PARTY" then n = n + 1 end end
    return n
end

return function(_, t)
    local sim = t.fresh(setup)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local Tile = MK.BriefingTile
    local tile = Tile:GetFrame()
    t.ok(tile ~= nil, "tile built when Marking starts")
    local function settle() sim:Advance(1) end

    -- A Trogg alone: nothing to brief.
    sim.units.nameplate1 = { name = "Ragefire Trogg", friendly = false, level = 14, tier = "elite", power = "RAGE" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    settle()
    t.ok(not tile:IsShown(), "only a Trogg: no tile")

    -- A Shaman joins: tile with its name.
    sim.units.nameplate2 = { name = "Ragefire Shaman", friendly = false, level = 13, tier = "elite", power = "MANA" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    settle()
    t.ok(tile:IsShown(), "caster in view: tile shown")
    t.eq(tile.label:GetText(), "Brief: Ragefire Shaman", "tile label names the mob")
    t.eq(Tile.current.lines[1], "[Bulwark] Interrupt: Ragefire Shaman: Healing Wave -> Tankard (Shield Bash)",
        "the tile offers the assignment")

    -- Click: posted, hidden until the briefing changes.
    tile:Click()
    t.eq(partyLines(sim), 2, "click posts the briefing (2 lines)")
    t.ok(not tile:IsShown(), "hidden after posting")
    settle()
    t.ok(not tile:IsShown(), "still hidden: same briefing")
    env.SetRaidTarget("nameplate2", 8)
    sim:Fire("RAID_TARGET_UPDATE")
    settle()
    t.ok(tile:IsShown(), "the briefing changed (skull on the Shaman): shown again")
    t.contains({ tile.label:GetText() }, "Ragefire Shaman", "label after marking")

    -- Combat hides it at once; it comes back after.
    sim:EnterCombat()
    sim:Fire("PLAYER_REGEN_DISABLED")
    t.ok(not tile:IsShown(), "hidden the moment combat starts")
    t.eq(Tile.Blocker(), "combat", "blocker: combat")
    sim:LeaveCombat()
    sim:Fire("PLAYER_REGEN_ENABLED")
    settle()
    t.ok(tile:IsShown(), "back after combat")

    -- Boss encounter and the Chat restriction.
    sim:Fire("ENCOUNTER_START", 2734, "Jergosh the Invoker", 1, 5)
    t.ok(not tile:IsShown(), "hidden at ENCOUNTER_START")
    settle()
    t.eq(Tile.Blocker(), "encounter", "blocker: encounter")
    sim:Fire("ENCOUNTER_END", 2734, "Jergosh the Invoker", 1, 5, 1)
    settle()
    t.ok(tile:IsShown(), "back after the encounter")
    sim.chatRestricted = true
    Tile:Refresh()
    t.ok(not tile:IsShown() and Tile.Blocker() == "chat", "hidden while addon chat is restricted")
    sim.chatRestricted = false
    Tile:Refresh()
    t.ok(tile:IsShown(), "back when chat is free")

    -- Solo: hidden unless testing.
    sim.group = "none"
    sim:Fire("GROUP_ROSTER_UPDATE")
    settle()
    t.ok(not tile:IsShown() and Tile.Blocker() == "solo", "solo: hidden")
    sim:Slash("/bwk mark brief test")
    t.ok(tile:IsShown(), "test mode: shown solo")
    sim:Slash("/bwk mark brief test")
    t.ok(not tile:IsShown(), "test mode off again")
    sim.group = "party"
    sim:Fire("GROUP_ROSTER_UPDATE")
    settle()

    -- Option off; open world.
    env.BulwarkDB.marking.briefTile = false
    Tile:Refresh()
    t.ok(not tile:IsShown() and Tile.Blocker() == "option", "option off: hidden")
    env.BulwarkDB.marking.briefTile = true
    MK.Plates.inInstance = false
    Tile:Refresh()
    t.ok(not tile:IsShown() and Tile.Blocker() == "world", "open world: hidden")
    MK.Plates.inInstance = true
    Tile:Refresh()
    t.ok(tile:IsShown(), "shown again")
    sim.output = {}
    sim:Slash("/bwk mark brief status")
    t.contains(sim.output, "Briefing tile shown: ", "status: shown")

    -- The key: one post per press although both click halves arrive.
    local before = partyLines(sim)
    env.BWK_BriefButton:Click()   -- registered for both halves, like a key binding: down + up
    t.eq(partyLines(sim) - before, 2, "key press posts once (2 lines)")
    t.ok(not tile:IsShown(), "hidden after the key post")

    -- A boss in view with nothing to kick: still a tile (the tank takes its worst cast).
    sim.units.nameplate1, sim.units.nameplate2 = nil, nil
    sim:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    sim:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    sim.units.nameplate3 = { name = "Jergosh the Invoker", friendly = false, level = 16, tier = "elite", power = "MANA" }
    sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    settle()
    t.ok(tile:IsShown(), "boss in view: tile")
    t.eq(tile.label:GetText(), "Brief: Jergosh the Invoker", "boss label")
    t.eq(Tile.current.lines[1], "[Bulwark] Interrupt: Jergosh the Invoker: Immolate -> Tankard (Shield Bash)", "boss line")

    -- Edit Mode: a sample to place, back to normal after.
    sim.units.nameplate3 = nil
    sim:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    settle()
    t.ok(not tile:IsShown(), "nothing in view: hidden")
    env.EditModeManagerFrame:TestEnter()
    t.ok(tile:IsShown(), "Edit Mode: sample shown")
    local box
    for _, el in ipairs(env.Bulwark.EditMode:GetElements()) do
        if el.label == "Bulwark briefing" then box = el.overlay end
    end
    t.ok(box and box:IsShown(), "Edit Mode box over the tile")
    tile:Click()
    t.eq(partyLines(sim), before + 2, "a click on the sample posts nothing")
    env.EditModeManagerFrame:TestExit()
    t.ok(not tile:IsShown(), "after Edit Mode: hidden again (nothing to brief)")

    -- Marking off: hidden; the key does nothing.
    env.Bulwark:SetAreaEnabled("marking", false)
    t.ok(not tile:IsShown(), "Marking off: hidden")
    t.eq(#sim.errors, 0, "no Lua errors")
end
