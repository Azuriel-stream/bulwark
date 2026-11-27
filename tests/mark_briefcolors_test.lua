-- Class colours for player names in announcements (user 2026-11-27). Player chat can't carry colour codes, so the
-- posted lines stay plain; names are coloured where Bulwark shows them: the preview, the solo print, and a chat
-- filter on party/raid lines that start with "[Bulwark]" (yours and other Bulwark users').
local H = require("mark_helpers")

local COLORS = { WARRIOR = { colorStr = "ffc69b6d" }, PRIEST = { colorStr = "ffffffff" },
                 SHAMAN = { colorStr = "ff0070dd" } }
local function c(name, class) return "|c" .. COLORS[class].colorStr .. name .. "|r" end

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        s.env.RAID_CLASS_COLORS = COLORS
        s.units.party2 = { name = "Kira", surname = "Stormcall", class = "SHAMAN", guid = "Player-1-00000003",
                           friendly = true, level = 20 }
    end)
    local MK = sim.env.Bulwark.Marking
    local B, Team = MK.Briefing, MK.Team
    sim.spells[11986] = "Healing Wave"
    sim.spells[72] = "Shield Bash"
    sim.spells[8042] = "Earth Shock"

    -- 1. Whole names only, each member in their class colour; other words untouched.
    local line = "[Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave -> Tankard (Shield Bash); "
        .. "Ragefire Shaman: Healing Wave -> Kira (Earth Shock)"
    t.eq(Team.ColorNames(line), "[Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave -> " .. c("Tankard", "WARRIOR")
        .. " (Shield Bash); Ragefire Shaman: Healing Wave -> " .. c("Kira", "SHAMAN") .. " (Earth Shock)",
        "tank and shaman coloured")
    t.eq(Team.ColorNames("[Bulwark] Note: Kiras and Tankards: Lumenfire"), "[Bulwark] Note: Kiras and Tankards: Lumenfire",
        "a name inside a longer word stays plain")
    t.eq(Team.ColorNames("[Bulwark] Tremor Totem -> Kira: Fear (Lumen)"),
        "[Bulwark] Tremor Totem -> " .. c("Kira", "SHAMAN") .. ": Fear (" .. c("Lumen", "PRIEST") .. ")", "totem line")
    t.eq(Team.ColorNames("Tankard", {}), "Tankard", "nobody to colour: unchanged")

    -- 2. The chat filters, run in order as the chat frame does (Alerts has one on the same events): our lines coloured,
    -- anything else passed through as it came; a secret message left alone.
    local function shown(event, msg, author)
        local n, hide = 0, false
        for _, f in ipairs(sim.chatFilters) do
            if f.event == event then
                n = n + 1
                hide, msg, author = f.fn(nil, event, msg, author)
                if hide then break end
            end
        end
        return n, hide, msg, author
    end
    for _, event in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }) do
        local n, hide, msg, author = shown(event, "[Bulwark] Tremor Totem -> Kira: Fear (Dark Caster)", "Tankard")
        t.ok(n > 0 and hide == false and author == "Tankard", event .. ": filtered, shown, other args kept")
        t.eq(msg, "[Bulwark] Tremor Totem -> " .. c("Kira", "SHAMAN") .. ": Fear (Dark Caster)", event .. ": coloured")
        local _, _, other = shown(event, "Kira, pull when ready", "Lumen")
        t.eq(other, "Kira, pull when ready", event .. ": someone else's line untouched")
        local secret = sim:maybeSecret("[Bulwark] Kira", true)
        local _, _, s = shown(event, secret)
        t.ok(s == secret, event .. ": secret message passed through")
    end

    -- 3. What goes out stays plain (colour codes can't be sent); the solo print is coloured.
    local mobs = { { name = "Ragefire Shaman", icon = 8, count = 1, spells = B.MobSpells({ "11986;heal;3000;allyhp;24;24;" }) } }
    local roster = B.Roster()
    B.Assign(mobs, { { short = "Tankard", class = "WARRIOR", tank = true, kit = B.KitFor("WARRIOR", 40, {
        known = function(ids) for _, id in ipairs(ids) do if id == 72 then return true end end end, shield = true }) } })
    local lines = B.BuildLines(mobs)
    Team:Send(lines)
    local posted = sim.chat[#sim.chat]
    t.eq(posted.channel, "PARTY", "posted to party")
    t.eq(posted.msg, "[Bulwark] Interrupt: {rt8} Ragefire Shaman: Healing Wave -> Tankard (Shield Bash)", "sent plain")
    t.ok(not posted.msg:find("|c", 1, true), "no colour code in chat")
    sim.group = "none"
    sim.output = {}
    Team:Send(lines)
    t.contains(sim.output, c("Tankard", "WARRIOR"), "solo print: name coloured")
    sim.group = "party"

    -- 4. The preview: interrupters, members without one and the would-post lines coloured.
    sim.output = {}
    local plan = B.Plan
    B.Plan = function() return mobs, { total = 1, noData = {}, unknown = 0 }, roster end
    B.Preview()
    B.Plan = plan
    local kira = c("Kira", "SHAMAN"):gsub("%p", "%%%0")
    t.contains(sim.output, "Interrupters: .*" .. kira, "interrupters: Kira in shaman blue")
    t.contains(sim.output, "No interrupt %(class/level%): .*" .. c("Lumen", "PRIEST"):gsub("%p", "%%%0"), "the priest coloured")
    t.contains(sim.output, "Healing Wave %-> " .. c("Tankard", "WARRIOR"):gsub("%p", "%%%0"), "would-post line coloured")
end
