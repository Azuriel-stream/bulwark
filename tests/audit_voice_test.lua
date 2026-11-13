-- Race voices + personalized requests (Voices.lua, kb/addons/Bulwark-Voices.md): the line pool follows the player's
-- race (option on) or Neutral; {who} = the one provider's first name, the plural class for several, nothing for a
-- mixed set of dispellers.
local H = require("audit_helpers")

-- Every message a pool can produce with these values (to check a sent line came from the right pool).
local function Possible(V, pool, vars)
    local out = {}
    for _, line in ipairs(pool) do out[V.Fill(line, vars)] = true end
    return out
end

local function Setup(race, faction)
    return function(s)
        H.Party(s)
        s.units.player.race = race
        s.units.player.faction = faction
        s.units.player.level = 60
        s.units.party1.level = 60
        s.forms = { { spellID = 71, active = true } }   -- Defensive Stance
    end
end

local function LastSent(w) return w.chat[#w.chat] end

return function(sim, t)
    local FORT = "[Power Word: Fortitude]"

    -- Windshaper Skyborne (race ID 96), one priest in the party: addressed by first name, Windshaper lines
    local w = t.fresh(Setup({ "Windshaper Skyborne", "Skyborne", 96 }, "Horde"))
    local V = w.env.Bulwark.AuditVoices
    local audit = w.env.BulwarkDB.audit
    t.eq(audit.raceVoice, true, "race voice on by default")
    t.eq((V.PlayerRace()), "WINDSHAPER", "race ID 96 -> Windshaper voice")
    H.Rescan(w)
    H.Find(w, "GROUP:FORTITUDE"):Click()
    local msg = LastSent(w).msg
    t.ok(Possible(V, V.DATA.WINDSHAPER.request, { who = "Lumen", spell = FORT })[msg], "Windshaper line to Lumen: " .. msg)
    t.ok(msg:find("^Lumen, "), "starts with the priest's first name: " .. msg)

    -- Two priests: the plural class
    w.units.party3 = { name = "Mira", surname = "Dawnsong", class = "PRIEST", guid = "Player-1-00000005",
                       friendly = true, level = 60, auras = {} }
    w:Fire("GROUP_ROSTER_UPDATE")
    w:Advance(6)
    H.Find(w, "GROUP:FORTITUDE"):Click()
    msg = LastSent(w).msg
    t.ok(msg:find("^Priests, "), "two priests -> 'Priests, ...': " .. msg)
    t.ok(Possible(V, V.DATA.WINDSHAPER.request, { who = "Priests", spell = FORT })[msg], "still a Windshaper line")

    -- Option off: Neutral per-buff lines, still personal
    audit.raceVoice = false
    w:Advance(6)
    H.Find(w, "GROUP:FORTITUDE"):Click()
    msg = LastSent(w).msg
    t.ok(Possible(V, V.DATA.NEUTRAL.requestByBuff.FORTITUDE, { who = "Priests", spell = FORT })[msg],
        "Neutral Fortitude line to Priests: " .. msg)
    audit.raceVoice = true

    -- Thank-you whisper in the race voice, to the caster by first name
    table.insert(w.units.player.auras, H.Aura(1243, "Power Word: Fortitude", { sourceUnit = "party3",
        expirationTime = w.now + 3600, duration = 3600 }))
    w:Advance(6)
    H.Rescan(w)
    local thanks = LastSent(w)
    t.eq(thanks.channel, "WHISPER", "thanks whispered")
    t.eq(thanks.target, "Mira Dawnsong", "to the caster's full name")
    t.ok(Possible(V, V.DATA.WINDSHAPER.thanks, { name = "Mira", spell = FORT })[thanks.msg], "Windshaper thanks: " .. thanks.msg)

    -- Blessing tile: one paladin -> by name
    local kings = H.Find(w, "BLESSING:KINGS")
    t.ok(kings, "Kings tile: " .. H.Keys(w))
    kings:Click()
    t.ok(LastSent(w).msg:find("^Aldric, "), "one paladin -> Aldric: " .. LastSent(w).msg)

    -- Dispel: Poison -> only the paladin can (priests can't) -> by name. Magic -> priests + paladin -> no address.
    local Bar = w.env.Bulwark.AuditBar
    w:Advance(6)
    Bar:GetDebuffTile("Poison").catcher:Click()
    msg = LastSent(w).msg
    t.ok(Possible(V, V.DATA.WINDSHAPER.dispelWho, { who = "Aldric", type = "Poison" })[msg], "Poison -> Aldric: " .. msg)
    Bar:GetDebuffTile("Magic").catcher:Click()
    msg = LastSent(w).msg
    t.ok(Possible(V, V.DATA.WINDSHAPER.dispelNoWho, { type = "Magic" })[msg], "Magic, mixed classes -> unaddressed: " .. msg)

    -- Healthstone: one warlock -> by name
    w.units.party4 = { name = "Vex", surname = "Grimshade", class = "WARLOCK", guid = "Player-1-00000006",
                       friendly = true, level = 60, auras = {} }
    w:Fire("GROUP_ROSTER_UPDATE")
    w:Advance(6)
    local hs = H.Find(w, "HEALTHSTONE")
    t.ok(hs, "Healthstone tile: " .. H.Keys(w))
    hs:Click()
    msg = LastSent(w).msg
    t.ok(Possible(V, V.DATA.WINDSHAPER.healthstone, { who = "Vex" })[msg], "Healthstone -> Vex: " .. msg)
    t.eq(#w.errors, 0, "no Lua errors")

    -- High Order Skyborne (race ID 95)
    local ho = t.fresh(Setup({ "High Order Skyborne", "Skyborne", 95 }, "Alliance"))
    t.eq((ho.env.Bulwark.AuditVoices.PlayerRace()), "HIGH_ORDER", "race ID 95 -> High Order voice")
    -- Unknown Skyborne ID: falls back to the faction
    local sk = t.fresh(Setup({ "Skyborne", "Skyborne", 999 }, "Horde"))
    t.eq((sk.env.Bulwark.AuditVoices.PlayerRace()), "WINDSHAPER", "Skyborne by name + Horde -> Windshaper")
    -- A race without a voice: Neutral lines
    local other = t.fresh(Setup({ "Pandaren", "Pandaren", 24 }, "Alliance"))
    local OV = other.env.Bulwark.AuditVoices
    local _, key = OV.Current()
    t.eq(key, "NEUTRAL", "race without a voice -> Neutral")
    -- Every voice has the pools it needs, and every request line addresses {who} first
    for name, voice in pairs(OV.DATA) do
        if name ~= "NEUTRAL" then
            for _, field in ipairs({ "request", "requestNoWho", "thanks", "dispelWho", "dispelNoWho", "healthstone" }) do
                t.ok(voice[field] and #voice[field] > 0, name .. "." .. field .. " present")
            end
            for _, line in ipairs(voice.request) do t.ok(line:find("^{who}, "), name .. " request starts with {who}: " .. line) end
            for _, line in ipairs(voice.requestNoWho) do t.ok(not line:find("{who}", 1, true), name .. " no-who line: " .. line) end
        end
    end

    -- Raid: the paladin aura is subgroup-only -> only the paladin in our subgroup counts, by name
    local r = t.fresh(function(s)
        Setup({ "Human", "Human", 1 }, "Alliance")(s)
        s.group = "raid"
        s.units.raid1 = s.units.player
        s.units.raid1.subgroup = 1
        s.units.raid2 = { name = "Aldric", surname = "Dawnward", class = "PALADIN", guid = "Player-1-00000003",
                          friendly = true, level = 60, subgroup = 1, auras = {} }
        s.units.raid3 = { name = "Brennan", surname = "Holt", class = "PALADIN", guid = "Player-1-00000007",
                          friendly = true, level = 60, subgroup = 2, auras = {} }
        s.units.party1, s.units.party2 = nil, nil
    end)
    H.Rescan(r)
    local aura = H.Find(r, "GROUP:PALADIN_AURA")
    t.ok(aura, "paladin aura tile in raid: " .. H.Keys(r))
    aura:Click()
    msg = LastSent(r).msg
    t.eq(LastSent(r).channel, "RAID", "raid request")
    t.ok(msg:find("^Aldric, "), "subgroup-only -> the paladin in our group: " .. msg)
    local RV = r.env.Bulwark.AuditVoices
    t.ok(Possible(RV, RV.DATA.HUMAN.request, { who = "Aldric", spell = "[Devotion Aura]" })[msg]
        or msg:find("Aura", 1, true), "Human line: " .. msg)
    -- Blessings count the whole raid: two paladins -> plural
    r:Advance(6)
    H.Find(r, "BLESSING:KINGS"):Click()
    t.ok(LastSent(r).msg:find("^Paladins, "), "two paladins in the raid -> Paladins: " .. LastSent(r).msg)
    t.eq(#r.errors, 0, "raid: no Lua errors")
end
