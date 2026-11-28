local ADDON_NAME, NS = ...
local Utils = NS.Utils

-- The open in-game checks (kb/testing.md, same ids). Delete an entry once it's confirmed. Questions are English only:
-- field tests are a development aid (off by default, /bwk tests on).
local FT = NS.FieldTests
local MANA_KEY = "CLICK BWK_ManaBreakButton:LeftButton"

local function InDungeon()
    local ok, inInstance, kind = pcall(IsInInstance)
    return ok and inInstance == true and kind == "party"
end

local function PartyUnits()
    local list = {}
    for i = 1, 4 do
        if UnitExists("party" .. i) then list[#list + 1] = "party" .. i end
    end
    return list
end

-- =========================================================================
-- Audit: mana break (kb/addons/Bulwark.md "Audit: mana break")
-- =========================================================================

FT:Define{
    id = "mana-key", kind = "auto", title = "Mana break: key binding",
    when = function() return GetBindingKey(MANA_KEY) ~= nil end,
    probe = function(d) d.key = GetBindingKey(MANA_KEY); return true end,
}

-- ManaBreak.lua reports the healer drinking; their mana itself is secret, so you're the judge.
FT:Define{
    id = "mana-healer-prompt", kind = "ask", title = "Mana break: healer prompt",
    question = function(d)
        local n = d.name or "Your healer"
        return string.format("%s is drinking.\n1. Before they sat down, did a prompt \"%s: N%% mana\" with their "
            .. "real mana appear by itself?\n2. Does it say \"%s is drinking\" now?\n3. Once they're back above "
            .. "the threshold, does it go away?\n(Later keeps this question until you've seen all three.)", n, n, n)
    end,
}

FT:Define{
    id = "mana-announce", kind = "ask", title = "Mana break: announcement",
    question = function(d)
        local who = d.kind == "healer" and ("naming " .. tostring(d.healer)) or "saying you need a drink"
        return string.format("Bulwark just posted a mana break line %s. Did exactly one line go to party chat, "
            .. "in the %s voice?", who, d.raceVoice and "race" or "plain (neutral)")
    end,
}

FT:Define{
    id = "mana-self-tile", kind = "ask", title = "Mana break: your drink tile",
    question = function(d)
        return string.format("Your drink tile is up (your mana: %d%%). Click it: did one \"I need a drink\" line "
            .. "go to party? Does the tile stay until you're back at 90%%?", d.pct or 0)
    end,
}

FT:Define{
    id = "mana-role-instance", kind = "auto", title = "Mana break: roles and mana inside a dungeon",
    when = function() return InDungeon() and #PartyUnits() > 0 end,
    probe = function(d)
        d.units = {}
        for _, u in ipairs(PartyUnits()) do
            local okR, role = pcall(UnitGroupRolesAssigned, u)
            local okM, mana = pcall(UnitPower, u, 0)
            d.units[u] = { role = okR and role or "error", manaSecret = okM and Utils.IsSecret(mana) or "error" }
        end
        return true
    end,
}

-- =========================================================================
-- Marking / Briefing (kb/addons/Bulwark-Briefing.md, Bulwark.md)
-- =========================================================================

-- Briefing.ReadMeter: a summon's hit credited to the creature, not its owner (session 54 fix).
FT:Define{ id = "bwk-summon-credit", kind = "auto", title = "Briefing: summon credited" }

-- Briefing.ReadMeter in a group: are the other members' meter rows readable? Done once one has rows, or after 10
-- group pulls where nobody else had any.
FT:Define{
    id = "brief-group-meter", kind = "auto", title = "Briefing: party members' meter rows",
    onSaw = function(d, _, p)
        d.pulls = (d.pulls or 0) + 1
        d.last = p
        if (p.othersWithRows or 0) > 0 then return "pass" end
        if d.pulls >= 10 then return "fail" end
    end,
}

-- Learn.IsPlayerRow skipped an enemy row that isn't you (a mind-controlled group member).
FT:Define{ id = "mark-charmed-row", kind = "auto", title = "Marking: charmed player skipped" }

-- Any boss: errors during the fight, threat and chat lockdown readings.
FT:Define{
    id = "boss-fight", kind = "auto", title = "Boss fight: errors, threat, chat",
    inCombat = true,
    events = {
        ENCOUNTER_START = function(d, st, id, name, difficulty, size)
            st.inFight, st.since = true, FT.Now()
            d.encounter = { id = id, name = name, difficulty = difficulty, size = size }
        end,
        ENCOUNTER_END = function(d, st, _, _, _, _, success)
            if not st.inFight then return end
            st.inFight = false
            d.success = success
            d.newErrors = FT.ErrorsSince(st.since)
            return #d.newErrors > 0 and "fail" or "auto"
        end,
    },
    when = function(d, st) return st.inFight and not d.threat and UnitExists("boss1") end,
    probe = function(d)
        d.threat = { pcall(UnitDetailedThreatSituation, "player", "boss1") }
        d.threatStatus = { pcall(UnitThreatSituation, "player", "boss1") }
        d.chatLockdown = { pcall(C_ChatInfo.InChatMessagingLockdown) }
        d.restrictions = Utils.ActiveRestrictions()
    end,
}

-- =========================================================================
-- Audit
-- =========================================================================

-- The old "Auras cannot be accessed" error (kb/gotchas.md#aura-boundary): 30 pulls without it = pass.
FT:Define{
    id = "audit-combat-boundary", kind = "auto", title = "Audit: aura reads at the combat boundary",
    events = {
        PLAYER_REGEN_DISABLED = function()
            local p = FT:Progress("audit-combat-boundary")
            p.since = p.since or FT.Now()
            p.pulls = (p.pulls or 0) + 1
        end,
        PLAYER_REGEN_ENABLED = function(d)
            local p = FT:Progress("audit-combat-boundary")
            if not p.since then return end
            local errs = FT.ErrorsSince(p.since, "cannot be accessed")
            d.pulls = p.pulls
            if #errs > 0 then d.errors = errs; return "fail" end
            if (p.pulls or 0) >= 30 then return "pass" end
        end,
    },
}

-- Scanner: someone else's weaker Battle Shout on you.
FT:Define{
    id = "audit-other-shout", kind = "ask", title = "Audit: someone else's weaker Battle Shout",
    question = function(d)
        return string.format("A weaker Battle Shout from someone else is on you (%s vs your %s).\n1. Is the red "
            .. "Battle Shout tile showing, and does its tooltip say someone else's weaker one is up?\n2. Click it: "
            .. "does it cast yours, and the tile goes away?", tostring(d.theirs), tostring(d.mine))
    end,
}

-- =========================================================================
-- Open facts (kb/testing.md section 3): recorded, nothing to answer
-- =========================================================================

-- GetRaidTargetIndex on a marked hostile target, out of and in combat.
FT:Define{
    id = "fact-raidtarget-marked", kind = "auto", title = "Fact: raid mark on a hostile target",
    inCombat = true,
    when = function()
        if not UnitExists("target") then return false end
        local ok, hostile = pcall(UnitCanAttack, "player", "target")
        return ok and hostile == true
    end,
    probe = function(d)
        local key = InCombatLockdown() and "inCombat" or "outOfCombat"
        if d[key] then return d.inCombat ~= nil and d.outOfCombat ~= nil end
        local ok, v = pcall(GetRaidTargetIndex, "target")
        if not ok then d[key] = { error = tostring(v) }
        elseif Utils.IsSecret(v) then d[key] = { secret = true }
        elseif v ~= nil then d[key] = { value = v } end
        return d.inCombat ~= nil and d.outOfCombat ~= nil
    end,
}

FT:Define{
    id = "fact-instance-id", kind = "auto", title = "Fact: GetInstanceInfo inside a dungeon",
    when = InDungeon,
    probe = function(d) d.info = { pcall(GetInstanceInfo) }; return true end,
}

-- Main-hand temporary enchant: two timeLeft readings 30 s apart tell the unit (ms or s).
FT:Define{
    id = "fact-enchant-timeleft", kind = "auto", title = "Fact: weapon enchant timeLeft unit",
    probe = function(d)
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0)
        if not ok or Utils.IsSecret(list) or type(list) ~= "table" then return end
        local info
        for _, e in ipairs(list) do
            if type(e) == "table" and e.hasEnchant == true and not Utils.IsSecret(e.timeLeft) then info = e; break end
        end
        if not info then return end
        if not d.first then
            d.first = { at = GetTime(), timeLeft = info.timeLeft, enchantID = info.enchantID }
        elseif GetTime() - d.first.at >= 30 then
            d.second = { at = GetTime(), timeLeft = info.timeLeft }
            return true
        end
    end,
    when = function() return true end,
}

-- Does C_Item.GetItemStats count a permanent enchant? Every worn enchanted item with and without its enchant field
-- (rev 2: rev 1 stopped at the first one, Mithril Spurs 464 on boots, which has no stats [in-game 2026-11-28]).
FT:Define{
    id = "gear-stats-enchant", kind = "auto", title = "Fact: GetItemStats and enchants", rev = 2,
    when = function() return true end,
    probe = function(d)
        d.items = {}
        for slot = 1, 18 do
            local link = GetInventoryItemLink("player", slot)
            local enchant = type(link) == "string" and not Utils.IsSecret(link) and link:match("item:%d+:(%d+)")
            if enchant and enchant ~= "0" then
                local bare = link:gsub("(item:%d+):%d+", "%1:")
                d.items[#d.items + 1] = { slot = slot, enchant = tonumber(enchant),
                    with = C_Item.GetItemStats(link), without = C_Item.GetItemStats(bare) }
            end
        end
        return #d.items > 0
    end,
}
