-- Learning real names and marks from the %t whisper echo (Learn.lua) and naming mobs in the announcement (Team.lua).
-- A dungeon out of combat is modelled with sim.restricted = true (mob names secret) while not in combat.
local H = require("mark_helpers")

return function(_, t)
    local sim = t.fresh(function(s)
        H.install(s)
        s.env.ICON_TAG_LIST = { rt1 = 1, rt4 = 4, rt8 = 8, star = 1, triangle = 4, skull = 8, ["totenschädel"] = 8 }
    end)
    local env = sim.env
    local MK = env.Bulwark.Marking
    local Learn, Team, Plates, Planner = MK.Learn, MK.Team, MK.Plates, MK.Planner
    local rows = env.BulwarkCharDB.marking.setup.rows

    -- Pure parsing.
    local n, icon, name = Learn.Parse("BWK~12~{rt4}Twilight Grunt")
    t.ok(n == 12 and icon == 4 and name == "Twilight Grunt", "marked: number, icon, name")
    n, icon, name = Learn.Parse("BWK~3~Krol'dok Brute")
    t.ok(n == 3 and icon == 0 and name == "Krol'dok Brute", "unmarked: icon 0")
    n, icon, name = Learn.Parse("BWK~5~<no target>")
    t.ok(n == 5 and name == nil, "no target: no name")
    n, icon, name = Learn.Parse("BWK~6~{Totenschädel}Höhlenwurm")
    t.ok(icon == 8 and name == "Höhlenwurm", "localized icon tag via ICON_TAG_LIST")
    t.ok(Learn.Parse("hello BWK~1~x") == nil, "other chat isn't ours")
    t.ok(Learn.IsOurs("BWK~1~%t") and not Learn.IsOurs("BWK says hi"), "IsOurs")

    -- Dungeon pack, names secret.
    H.pack(sim)
    sim.restricted = true
    for i = 1, 3 do sim:Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    sim:Advance(1)
    local rec1, rec2 = Plates.records.nameplate1, Plates.records.nameplate2
    t.ok(rec1 and rec1.name == nil, "name secret, so not read")

    local function Target(token)
        sim.units.target = token and sim.units[token] or nil
        sim:Fire("PLAYER_TARGET_CHANGED")
    end
    local function LastChat() return sim.chat[#sim.chat] end

    Target("nameplate2")
    local sent = LastChat()
    t.ok(sent and sent.msg == "BWK~1~%t", "target change whispers %t with a sequence number")
    t.ok(sent.channel == "WHISPER" and sent.target == "Tankard Stoneforge", "whisper to yourself (First Last)")
    sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~1~{rt4}Ragefire Shaman", "Tankard Stoneforge")
    t.ok(rec2.learnedName == "Ragefire Shaman" and rec2.learnedIcon == 4, "echo teaches name and mark")
    t.eq(MK.MobDB:Label(rec2), "Ragefire Shaman", "plan/overlay label uses the learned name")

    -- Throttle: a quick second target change waits, then sends for the current target.
    local count = #sim.chat
    Target("nameplate1")
    t.eq(#sim.chat, count, "too soon after the last whisper: waits")
    sim:Advance(0.5)
    t.ok(#sim.chat == count + 1 and LastChat().msg == "BWK~2~%t", "sent after the gap")
    sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~2~Ragefire Trogg", "Tankard Stoneforge")
    t.ok(rec1.learnedName == "Ragefire Trogg" and rec1.learnedIcon == 0, "unmarked mob learned")

    -- Already learned: no whisper. A mark change makes it worth asking again.
    sim:Advance(1)
    count = #sim.chat
    Target("nameplate2")
    t.eq(#sim.chat, count, "known mob, marks unchanged: no whisper")
    sim:Fire("RAID_TARGET_UPDATE")
    t.eq(Learn.MarkOf(rec2), nil, "a mark change makes learned marks unknown")
    sim:Advance(1)
    t.eq(#sim.chat, count + 1, "after a mark change the current target is asked again")

    -- Unknown, stale or foreign echoes change nothing.
    sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~99~{rt8}Nobody", "Tankard Stoneforge")
    t.ok(rec1.learnedName == "Ragefire Trogg", "an echo we didn't send is ignored")

    -- No whispers in boss fights, under the Chat restriction, or with the option off.
    sim:Advance(1)
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    count = #sim.chat
    sim:Fire("ENCOUNTER_START", 2733, "Taragaman the Hungerer", 1, 5)
    Target("nameplate3")
    sim:Advance(1)
    t.eq(#sim.chat, count, "no whisper during an encounter")
    sim:Fire("ENCOUNTER_END", 2733, "Taragaman the Hungerer", 1, 5, 1)
    sim.chatRestricted = true
    Target("nameplate1")
    sim:Advance(1)
    t.eq(#sim.chat, count, "no whisper while addon chat is restricted")
    sim.chatRestricted = false
    env.BulwarkDB.marking.learnNames = false
    Target("nameplate3")
    sim:Advance(1)
    t.eq(#sim.chat, count, "no whisper with the option off")
    env.BulwarkDB.marking.learnNames = true
    Target("nameplate3")
    sim:Advance(1)
    t.eq(#sim.chat, count + 1, "whispers again once allowed")

    -- An echo for a plate that was removed meanwhile is dropped.
    local pendingN = tonumber(LastChat().msg:match("^BWK~(%d+)~"))
    sim:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~" .. pendingN .. "~Ragefire Trogg", "Tankard Stoneforge")
    t.ok(Plates.records.nameplate3 == nil, "plate gone")

    -- Chat filter hides our whispers, not others.
    local filtered = 0
    for _, f in ipairs(sim.chatFilters) do
        if f.event == "CHAT_MSG_WHISPER" or f.event == "CHAT_MSG_WHISPER_INFORM" then
            if f.fn(nil, f.event, "BWK~1~{rt4}Ragefire Shaman") == true then filtered = filtered + 1 end
            t.ok(f.fn(nil, f.event, "hi there") == false, "other whispers pass")
        end
    end
    t.eq(filtered, 2, "both whisper events filtered")

    -- Announcement: our skull on the trogg, someone's triangle on the shaman (learned after the last mark change).
    sim:Fire("RAID_TARGET_UPDATE")
    sim:Advance(1)
    rec2.learnedIcon, rec2.learnedEpoch = nil, nil
    Target("nameplate2")
    sim:Advance(1)
    local m = tonumber(LastChat().msg:match("^BWK~(%d+)~"))
    sim:Fire("CHAT_MSG_WHISPER_INFORM", "BWK~" .. m .. "~{rt4}Ragefire Shaman", "Tankard Stoneforge")
    Planner.placed[8] = rec1
    rows[1].player = "Tankard Stoneforge"
    local lines = Team:BuildAnnouncement()
    t.eq(lines[1], "[Bulwark] Kill order: {rt8} Ragefire Trogg (Tankard) > {rt4} Ragefire Shaman", "kill line names the pack")
    rows[5].role, rows[5].player = "CC", "Lumen Brightwater"   -- triangle becomes Lumen's
    sim.units.party1.class = "MAGE"
    lines = Team:BuildAnnouncement()
    t.eq(lines[1], "[Bulwark] Kill order: {rt8} Ragefire Trogg (Tankard)", "kill line without the CC mob")
    t.eq(lines[2], "[Bulwark] CC: {rt4} Ragefire Shaman: Lumen (Polymorph)", "CC line names the mob")
    rows[5].role, rows[5].player = "TANK", nil

    -- No known mob on any kill icon: the old full list.
    Planner.placed[8] = nil
    sim:Fire("RAID_TARGET_UPDATE")
    lines = Team:BuildAnnouncement()
    t.eq(lines[1], "[Bulwark] Kill order: {rt8} Tankard > {rt7} > {rt6} > {rt5} > {rt4} > {rt3} > {rt2} > {rt1}",
        "fallback: every kill icon")

    -- Long lists wrap under the chat limit, each line labelled.
    for i = 1, 8 do
        local token = "nameplate" .. (10 + i)
        sim.units[token] = { name = "x", friendly = false, level = 15, tier = "elite" }
        sim:Fire("NAME_PLATE_UNIT_ADDED", token)
        Plates.records[token].learnedName = "A Very Long Dungeon Mob Name Number " .. i
        Planner.placed[i] = Plates.records[token]
    end
    lines = Team:BuildAnnouncement()
    t.ok(#lines >= 2, "8 long names need more than one line")
    for _, l in ipairs(lines) do
        t.ok(#l <= 250, "line within the chat limit")
        t.ok(l:find("^%[Bulwark%] Kill order: "), "every line has the label")
    end
end
