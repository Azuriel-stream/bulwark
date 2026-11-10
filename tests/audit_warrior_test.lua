-- Warrior tank: checklist tiles, Blizzard slots, clicks, gratitude, combat freeze.
local H = require("audit_helpers")

return function(sim, t)
    -- Solo, Battle Shout not learned: nothing to check
    t.eq(#H.Shown(sim), 0, "solo warrior without Battle Shout shows nothing")

    -- Consumables solo: off by default (above); "Solo" ticked -> food and weapon tiles, elixir/flask add-on too
    local solo = t.fresh(function(s)
        H.Party(s)
        s.group = "none"                             -- really ungrouped (the sim starts in a party)
    end)
    local audit = solo.env.BulwarkDB.audit
    t.eq(audit.consumablesSolo, false, "solo consumables off by default")
    t.eq(audit.consumablesInGroup, true, "group consumables on by default")
    H.Rescan(solo)
    t.eq(#H.Shown(solo), 0, "solo, defaults: no consumable tiles: " .. H.Keys(solo))
    audit.consumablesSolo = true
    audit.consumableLevel = 3
    H.Rescan(solo)
    for _, key in ipairs({ "CONS:WELL_FED", "CONS:WEAPON_BUFF", "CONS:FLASK" }) do
        t.ok(H.Find(solo, key), "solo consumables: " .. key .. " expected in: " .. H.Keys(solo))
    end
    t.ok(not H.Find(solo, "HEALTHSTONE") and not H.Find(solo, "GROUP:FORTITUDE"), "solo: still no group tiles: " .. H.Keys(solo))
    audit.checkConsumables = false
    H.Rescan(solo)
    t.eq(#H.Shown(solo), 0, "Consumables master switch off wins over Solo")

    local w = t.fresh(function(s)
        H.Party(s)
        s.known[6673] = true                         -- Battle Shout
        s.known[71] = true                           -- Defensive Stance (known, not active)
        s.forms = { { spellID = 2457, active = true }, { spellID = 71, active = false } }
    end)
    H.Rescan(w)

    -- Checklist contents and order (self buffs first)
    local keys = H.Keys(w)
    t.eq(H.Shown(w)[1].item.tileKey, "SELF:BATTLE_SHOUT", "self buff first: " .. keys)
    for _, key in ipairs({ "SELF:DEFENSIVE_STANCE", "GROUP:FORTITUDE", "GROUP:PALADIN_AURA",
                           "BLESSING:KINGS", "CONS:WELL_FED", "CONS:WEAPON_BUFF" }) do
        t.ok(H.Find(w, key), key .. " expected in: " .. keys)
    end
    for _, key in ipairs({ "GROUP:ARCANE_INTELLECT", "GROUP:SPIRIT", "GROUP:BATTLE_SHOUT", "BLESSING:MIGHT", "HEALTHSTONE", "CONS:FLASK" }) do
        t.ok(not H.Find(w, key), key .. " not expected in: " .. keys)
    end

    -- Battle Shout tile: casts when clicked (missing), Blizzard slot filtered to every rank, red under 15 s
    local bs = H.Find(w, "SELF:BATTLE_SHOUT")
    t.eq(bs:GetAttribute("type"), "spell", "Battle Shout tile casts")
    t.eq(bs:GetAttribute("spell"), "Battle Shout", "casts Battle Shout")
    bs:Click()
    t.eq(w.casts[#w.casts].spell, "Battle Shout", "secure cast performed (down-click)")
    local slot = H.Container(w, bs)._slots.tile
    t.ok(slot._options.candidateFilters.includeSpellIDs[6192], "slot includes Battle Shout rank 3")
    t.eq(slot._filter, "HELPFUL", "slot shows helpful auras")
    local curve = slot._SetDurationText.options.textColor.curve
    t.eq(curve.points[2].x, 15, "countdown turns red at 15 s")

    -- Elixir tile covers Forever's renamed/new elixirs ([in-game] dump: 673 = Elixir of Minor Defense)
    w.env.BulwarkDB.audit.consumableLevel = 2
    H.Rescan(w)
    local elixirSlot = H.Container(w, w.env.Bulwark.AuditBar:GetTile("CONS:ELIXIR"))._slots.tile
    local elixirIds = elixirSlot._options.candidateFilters.includeSpellIDs
    t.ok(elixirIds[673] and elixirIds[1250920] and elixirIds[17538], "elixir tile: Minor Defense, Phalanx, Mongoose")
    t.ok(not elixirIds[7178], "utility draughts (water breathing) don't count as an elixir")
    w.env.BulwarkDB.audit.consumableLevel = 1
    H.Rescan(w)

    -- "In a group" unticked: no consumable tiles in the party (other tiles unaffected)
    w.env.BulwarkDB.audit.consumablesInGroup = false
    H.Rescan(w)
    t.ok(not H.Find(w, "CONS:WELL_FED") and not H.Find(w, "CONS:WEAPON_BUFF"), "group consumables off: " .. H.Keys(w))
    t.ok(H.Find(w, "GROUP:FORTITUDE"), "group buffs still checked")
    w.env.BulwarkDB.audit.consumablesSolo = true
    H.Rescan(w)
    t.ok(not H.Find(w, "CONS:WELL_FED"), "Solo ticked doesn't apply in a party")
    w.env.BulwarkDB.audit.consumablesInGroup, w.env.BulwarkDB.audit.consumablesSolo = true, false
    H.Rescan(w)

    -- Weapon tile uses Blizzard's item-enchant display, sized by us
    local weapon = H.Find(w, "CONS:WEAPON_BUFF")
    local enchant = H.Container(w, weapon)._enchant
    t.ok(enchant and enchant._enchantSlot == 0, "weapon tile shows the main-hand enchant")

    -- "No tiles = all good": a buff that's up hides its tile (waiting invisibly, not clickable)
    table.insert(w.units.player.auras, H.Aura(6192, "Battle Shout", { duration = 180, expirationTime = w.now + 180 }))
    H.Rescan(w)
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "Battle Shout up -> tile hidden")
    local waitingBs = H.Planned(w, "SELF:BATTLE_SHOUT")
    t.ok(waitingBs and waitingBs:GetAlpha() == 0 and not waitingBs:IsMouseEnabled(), "waits invisible and unclickable")
    t.eq(H.Shown(w)[1].item.tileKey, "SELF:DEFENSIVE_STANCE", "visible tiles packed first")
    -- ...and fades back in for its last 15 s (out of combat: from the readable aura)
    w:Advance(166)
    t.ok(H.Find(w, "SELF:BATTLE_SHOUT"), "Battle Shout tile reappears in its warning window")
    -- refresh it for the rest of the test
    w.units.player.auras[#w.units.player.auras].expirationTime = w.now + 180
    H.Rescan(w)
    t.ok(not H.Find(w, "SELF:BATTLE_SHOUT"), "refreshed -> hidden again")

    -- Group buff tile: click asks the party; throttled; gratitude whisper when it arrives
    local fort = H.Find(w, "GROUP:FORTITUDE")
    t.eq(fort:GetAttribute("type"), nil, "request tiles have no secure action")
    -- Addon chat restricted: blocked even from a click [in-game]; the player is told, nothing sent, not throttled.
    w.chatRestricted = true
    fort:Click()
    w.chatRestricted = false
    t.eq(#w.chat, 0, "restricted: request not sent")
    t.contains(w.output, "doesn't let addons send chat", "restricted: player told")
    t.eq(#w.violations, 0, "restricted: no blocked action")
    fort:Click()
    local req = t.contains(w.chat, "Fortitude", "request sent")
    t.eq(req.channel, "PARTY", "request goes to party")
    -- Ranked spell links corrupt the rest of a sent chat message on Forever: names go out as plain text.
    t.ok(not req.msg:find("|H", 1, true), "request contains no spell link")
    t.ok(req.msg:find("[Power Word: Fortitude]", 1, true), "request names the spell as plain [Name]")
    t.eq(#w.chat, 1, "one click sends one message (hook acts on the up half only)")
    fort:Click()
    t.eq(#w.chat, 1, "requests are throttled")
    table.insert(w.units.player.auras, H.Aura(1243, "Power Word: Fortitude", { sourceUnit = "party1",
        expirationTime = w.now + 3600, duration = 3600 }))
    H.Rescan(w)
    local thanks = w.chat[#w.chat]
    t.eq(thanks.channel, "WHISPER", "gratitude is a whisper")
    t.eq(thanks.target, "Lumen Brightwater", "whispers the caster by full Forever name")
    t.ok(not thanks.msg:find("|H", 1, true), "gratitude contains no spell link")
    t.ok(thanks.msg:find("[Power Word: Fortitude]", 1, true), "gratitude names the spell as plain [Name]")

    -- Clicked while expiring: the old copy still on us is not the answer; only the recast earns a thank-you
    local fortAura = w.units.player.auras[#w.units.player.auras]
    fortAura.expirationTime = w.now + 30
    w:Advance(6)                                     -- past the request throttle; replans with the expiring buff
    fort = H.Find(w, "GROUP:FORTITUDE")
    t.ok(fort, "expiring Fortitude tile shown: " .. H.Keys(w))
    local chatCount = #w.chat
    fort:Click()
    t.eq(#w.chat, chatCount + 1, "expiring request sent")
    w:Advance(4)                                     -- several scans with the old buff still up
    t.eq(#w.chat, chatCount + 1, "no thanks for the buff we already had")
    fortAura.expirationTime = w.now + 3600           -- the priest recasts
    H.Rescan(w)
    t.eq(#w.chat, chatCount + 2, "thanks once the buff is recast")
    t.eq(w.chat[#w.chat].channel, "WHISPER", "the recast earns the whisper")

    -- Top row: Salvation watch + one debuff tile per type the group can remove (priest: Magic/Disease, paladin: +Poison)
    local Bar = w.env.Bulwark.AuditBar
    t.ok(Bar:GetSalvationHolder():IsShown(), "Salvation slot watched")
    for _, dtype in ipairs({ "Magic", "Disease", "Poison" }) do
        t.ok(Bar:GetDebuffTile(dtype):IsShown(), dtype .. " debuff tile shown")
    end
    t.ok(not Bar:GetDebuffTile("Curse"):IsShown(), "nobody removes curses -> no Curse tile")
    local poison = Bar:GetDebuffTile("Poison")
    t.ok(not poison.bg:IsShown(), "empty debuff tile is invisible (no square) when not previewing")
    local poisonSlot = H.Container(w, poison)._slots.debuff
    t.ok(poisonSlot._options.candidateFilters.includeDispelTypes.Poison, "Blizzard slot shows Poison debuffs")
    -- Blizzard's debuff button swallows clicks, so our catcher sits on top and asks for a dispel
    t.eq(poison.catcher:GetAttribute("type"), nil, "warrior can't dispel: catcher requests")
    local chatBefore = #w.chat
    poison.catcher:Click()
    t.eq(#w.chat, chatBefore + 1, "one dispel request per click")
    t.ok(w.chat[#w.chat].msg:find("Poison"), "request names the dispel type")

    -- Combat freezes the layout: roster change in combat applies afterwards, with no protected changes
    local before = H.Keys(w)
    w:EnterCombat()
    w.units.party3 = { name = "Fern", surname = "Oakhollow", class = "DRUID", guid = "Player-1-00000004",
                       friendly = true, level = 60, auras = {} }
    w:Fire("GROUP_ROSTER_UPDATE")
    w:Advance(5)
    t.eq(H.Keys(w), before, "layout frozen in combat")
    -- Unlocking (or opening the Audit tab) mid-fight requests a preview layout directly: it must wait for combat to end
    w:Slash("/bwk audit unlock")
    w:Slash("/bwk audit")   -- open the Audit tab (preview) mid-fight
    t.eq(#w.violations, 0, "no protected-frame changes in combat")
    w:Slash("/bwk")         -- close the window
    w:Slash("/bwk audit lock")
    w:LeaveCombat()
    w:Advance(1)
    t.ok(H.Find(w, "GROUP:MARK_OF_THE_WILD"), "druid's Mark of the Wild tile appears after combat")
    t.ok(Bar:GetDebuffTile("Curse"):IsShown(), "level 60 druid adds a Curse tile after combat")

    -- Dispel levels: a level 15 paladin (Purify at 8, Cleanse at 42) covers Poison/Disease but not Magic
    local low = t.fresh(function(s)
        H.Party(s)
        s.units.party1 = s.units.party2     -- the paladin is the only party member (slots are contiguous in-game)
        s.units.party2 = nil
        s.units.party1.level = 15           -- low-level paladin
    end)
    H.Rescan(low)
    local LB = low.env.Bulwark.AuditBar
    t.ok(LB:GetDebuffTile("Poison"):IsShown() and LB:GetDebuffTile("Disease"):IsShown(), "level 15 paladin: Poison/Disease")
    t.ok(not LB:GetDebuffTile("Magic"):IsShown(), "level 15 paladin can't Cleanse yet: no Magic tile")
end
