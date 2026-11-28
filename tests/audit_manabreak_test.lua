-- Mana break (5-man groups): your own tile (plain mana), the healer prompt driven by SECRET mana (curve -> alpha, never
-- compared in Lua), drinking, healer detection, the key / command, voices, blockers, previews.
local H = require("audit_helpers")

return function(sim, t)
    local function party(s, healerMana, extra)
        H.Party(s)                                      -- party1 Lumen (priest), party2 Aldric (paladin)
        s.spells[430] = "Drink"
        s.spells[167152] = "Refreshment"
        s.units.party1.mana = { healerMana or 30, 100 }
        s.units.party1.role = "HEALER"
        s.units.party2.mana = { 100, 100 }
        s.units.party2.role = "DAMAGER"
        if extra then extra(s) end
    end
    local function frames(w) return w.env.Bulwark.AuditManaBreak:GetFrames() end
    local function settle(w)
        w:Fire("GROUP_ROSTER_UPDATE")
        w:Advance(1)
    end
    local function alpha(w)
        local _, _, prompt = frames(w)
        return w:Reveal(prompt:GetAlpha())
    end

    ------------------------------------------------------------------ warrior + priest healer at 30 %
    local w = t.fresh(function(s) party(s, 30) end)
    w.env.BulwarkDB.audit.raceVoice = false
    settle(w)
    local frame, selfTile, prompt = frames(w)
    t.ok(frame and frame:IsShown(), "5-man, out of combat: frame shown")
    t.ok(not selfTile:IsShown(), "warrior (no mana): no own tile")
    t.ok(prompt:IsShown(), "healer prompt shown")
    t.ok(w.env.issecretvalue(prompt:GetAlpha()), "prompt alpha comes from the secret curve result")
    t.eq(alpha(w), 1, "healer at 30% (< 40%): prompt visible")
    t.eq(prompt.label._text, "Lumen: 30% mana", "prompt text = name + secret % via SetFormattedText")
    t.eq(prompt:IsMouseEnabled(), false, "prompt never takes the mouse")
    t.eq(w.env.Bulwark.AuditManaBreak.healerHow, "role", "healer found by group role")

    -- Healer back to 85 %: invisible (alpha 0), still no Lua comparison of the secret
    w.units.party1.mana = { 85, 100 }
    w:Fire("UNIT_POWER_UPDATE", "party1", "MANA")
    w:Advance(1)
    t.eq(alpha(w), 0, "healer at 85%: prompt invisible")

    -- Threshold edge: 39 % shows, 40 % doesn't
    w.units.party1.mana = { 39, 100 }
    w:Fire("UNIT_POWER_UPDATE", "party1", "MANA"); w:Advance(1)
    t.eq(alpha(w), 1, "39%: visible")
    w.units.party1.mana = { 40, 100 }
    w:Fire("UNIT_POWER_UPDATE", "party1", "MANA"); w:Advance(1)
    t.eq(alpha(w), 0, "40%: invisible")

    -- Drinking at 85 %: fully shown, plain text
    w.units.party1.mana = { 85, 100 }
    w.units.party1.auras = { H.Aura(1137, "Drink") }
    w:Fire("UNIT_AURA", "party1", { isFullUpdate = true }); w:Advance(1)
    t.eq(alpha(w), 1, "drinking: shown above the threshold")
    t.eq(prompt.label._text, "Lumen is drinking", "drinking label")
    w.units.party1.auras = { H.Aura(167152, "Refreshment") }
    w:Fire("UNIT_AURA", "party1", { isFullUpdate = true }); w:Advance(1)
    t.eq(prompt.label._text, "Lumen is drinking", "Refreshment counts as drinking")
    w.units.party1.auras = {}
    w:Fire("UNIT_AURA", "party1", { isFullUpdate = true }); w:Advance(1)
    t.eq(alpha(w), 0, "stopped drinking at 85%: invisible again")

    -- Key: announces the healer, throttled, party chat
    w.units.party1.mana = { 20, 100 }
    w:Fire("UNIT_POWER_UPDATE", "party1", "MANA"); w:Advance(1)
    w.env.BWK_ManaBreakButton:Click()
    t.eq(#w.chat, 1, "key: one message")
    t.eq(w.chat[1].channel, "PARTY", "key: party channel")
    t.ok(w.chat[1].msg:find("Lumen", 1, true), "key: names the healer: " .. tostring(w.chat[1].msg))
    w:Advance(1)
    w.env.BWK_ManaBreakButton:Click()
    t.eq(#w.chat, 1, "key again within 10 s: throttled")
    w:Advance(11)
    w.chatRestricted = true
    w.env.BWK_ManaBreakButton:Click()
    t.eq(#w.chat, 1, "chat restricted: nothing sent")
    t.eq(#w.violations, 0, "chat restricted: no blocked action")
    w.chatRestricted = false

    -- Combat: hidden at once; back after
    w:EnterCombat()
    t.ok(not frame:IsShown(), "combat: hidden")
    w:LeaveCombat()
    w:Advance(1)
    t.ok(frame:IsShown(), "after combat: shown again")

    -- Healer dead: no prompt (its mana would read 0)
    w.units.party1.dead = true
    w:Fire("UNIT_HEALTH", "party1"); w:Advance(1)
    t.ok(not prompt:IsShown(), "dead healer: no prompt")
    w.units.party1.dead = false
    w:Fire("UNIT_HEALTH", "party1"); w:Advance(1)
    t.ok(prompt:IsShown(), "healer alive again: prompt")

    -- Resting, raid, solo, options off
    w.resting = true
    w:Fire("PLAYER_UPDATE_RESTING"); w:Advance(1)
    t.ok(not frame:IsShown(), "resting: hidden")
    w.resting = false
    w:Fire("PLAYER_UPDATE_RESTING"); w:Advance(1)
    w.group = "raid"
    settle(w)
    t.ok(not frame:IsShown(), "raid: hidden")
    w.env.BWK_ManaBreakButton:Click()
    t.eq(#w.chat, 1, "raid: key sends nothing")
    w.group = "party"
    settle(w)
    w.env.BulwarkDB.audit.manaHealer = false
    settle(w)
    t.ok(not prompt:IsShown(), "healer option off: no prompt")
    w.env.BulwarkDB.audit.manaHealer = true
    w.env.BulwarkDB.audit.manaBreak = false
    settle(w)
    t.ok(not frame:IsShown(), "master off: hidden")
    w.env.BulwarkDB.audit.manaBreak = true
    settle(w)

    -- Threshold setting moves the edge
    w.units.party1.mana = { 55, 100 }
    w.env.BulwarkDB.audit.manaThreshold = 60
    settle(w)
    t.eq(alpha(w), 1, "threshold 60: 55% visible")

    -- Status + command
    w:Slash("/bwk audit mana status")
    t.ok(table.concat(w.output, "\n"):find("Lumen", 1, true), "status names the healer")
    t.eq(#w.errors, 0, "warrior run: no errors: " .. (w.errors[1] and w.errors[1].err or ""))

    ------------------------------------------------------------------ healer detection without roles
    local d = t.fresh(function(s)
        party(s, 30, function(x) x.units.party1.role = nil; x.units.party2.role = nil end)
    end)
    settle(d)
    local _, _, dPrompt = frames(d)
    t.ok(not dPrompt:IsShown(), "no roles, priest + paladin: nobody guessed")
    d:Slash("/bwk audit mana healer")
    t.eq(#d.chat, 0, "no healer: nothing sent")
    d.env.BulwarkDB.audit.manaHealerPick = "Aldric"
    settle(d)
    t.ok(dPrompt:IsShown(), "picked healer: prompt")
    t.eq(d.env.Bulwark.AuditManaBreak.healerName, "Aldric", "the picked player")
    d.env.BulwarkDB.audit.manaHealerPick = ""
    d.units.party2.class = "WARRIOR"
    settle(d)
    t.eq(d.env.Bulwark.AuditManaBreak.healerName, "Lumen", "only one healing class: guessed")
    t.eq(d.env.Bulwark.AuditManaBreak.healerHow, "class", "guessed by class")

    ------------------------------------------------------------------ paladin tank: own mana tile
    local p = t.fresh(function(s)
        s.units.player.class = "PALADIN"
        party(s, 100)
        s.units.player.mana = { 30, 100 }
    end)
    p.env.BulwarkDB.audit.raceVoice = false
    settle(p)
    local _, pSelf = frames(p)
    t.ok(pSelf:IsShown(), "paladin at 30%: own tile")
    t.eq(p:Reveal(select(3, frames(p)):GetAlpha()), 0, "healer full: prompt invisible")
    pSelf:Click()
    t.eq(#p.chat, 1, "own tile click: one message")
    local NEUTRAL = p.env.Bulwark.AuditVoices.DATA.NEUTRAL.manaSelf
    local found = false
    for _, line in ipairs(NEUTRAL) do if line == p.chat[1].msg then found = true end end
    t.ok(found, "own tile: a neutral 'I need a drink' line: " .. tostring(p.chat[1].msg))

    -- Hysteresis: stays while drinking up, goes at 90 %
    p.units.player.mana = { 60, 100 }
    p:Fire("UNIT_POWER_UPDATE", "player", "MANA"); p:Advance(1)
    t.ok(pSelf:IsShown(), "60%: tile stays (until 90%)")
    p.units.player.mana = { 92, 100 }
    p:Fire("UNIT_POWER_UPDATE", "player", "MANA"); p:Advance(1)
    t.ok(not pSelf:IsShown(), "92%: tile gone")
    -- A pull clears it: below threshold -> fight -> after the fight at 60 % no tile
    p.units.player.mana = { 30, 100 }
    p:Fire("UNIT_POWER_UPDATE", "player", "MANA"); p:Advance(1)
    t.ok(pSelf:IsShown(), "30% again: tile")
    p:EnterCombat()
    p.units.player.mana = { 60, 100 }
    p:LeaveCombat(); p:Advance(1)
    t.ok(not pSelf:IsShown(), "pulled anyway: tile cleared, 60% doesn't bring it back")
    p.env.BulwarkDB.audit.manaSelf = false
    p.units.player.mana = { 10, 100 }
    settle(p)
    t.ok(not pSelf:IsShown(), "own mana option off: no tile")

    t.eq(#p.errors, 0, "paladin run: no errors: " .. (p.errors[1] and p.errors[1].err or ""))

    ------------------------------------------------------------------ voices: every voice has both pools, {name} filled
    local V = w.env.Bulwark.AuditVoices
    for key, voice in pairs(V.DATA) do
        t.ok(voice.manaSelf and #voice.manaSelf >= 2, key .. ": manaSelf lines")
        t.ok(voice.manaHealer and #voice.manaHealer >= 2, key .. ": manaHealer lines")
        for _, line in ipairs(voice.manaHealer) do
            t.ok(line:find("{name}", 1, true), key .. ": healer line names the healer: " .. line)
            t.ok(#line:gsub("{name}", "Thalindrastra") <= 255, key .. ": fits a chat line")
        end
        for _, line in ipairs(voice.manaSelf) do
            t.ok(not line:find("{", 1, true), key .. ": self line has no placeholder: " .. line)
        end
    end

    ------------------------------------------------------------------ previews: Edit Mode / Audit tab show both parts
    local v = t.fresh(function(s) party(s, 100) end)
    v.group = "none"
    settle(v)
    local vFrame, vSelf, vPrompt = frames(v)
    t.ok(not vFrame:IsShown(), "solo: hidden")
    v.env.Bulwark.Window:Open("audit", "mana")
    v:Advance(1)
    t.ok(vFrame:IsShown() and vSelf:IsShown() and vPrompt:IsShown(), "Audit tab open: sample shown")
    vSelf:Click()
    t.eq(#v.chat, 0, "sample click sends nothing")
    v:Slash("/bwk")   -- toggles the window closed
    v:Advance(1)
    t.ok(not v.env.Bulwark.Window:IsShown(), "window closed")
    t.ok(not vFrame:IsShown(), "window closed: hidden again (solo)")
    v:Slash("/bwk audit mana status")
    t.ok(table.concat(v.output, "\n"):find("not in a group", 1, true), "status says why")
    t.eq(#v.errors, 0, "preview run: no errors: " .. (v.errors[1] and v.errors[1].err or ""))
end
