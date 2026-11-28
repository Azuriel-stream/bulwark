-- Field tests (Core/FieldTests.lua + FieldTestList.lua): off by default, popups only out of combat and one at a time,
-- Pass / Fail with a note / Later / Skip, auto probes, Saw() from feature code, secrets never reach SavedVariables.
local H = require("audit_helpers")

return function(sim, t)
    local function FT(w) return w.env.Bulwark.FieldTests end
    local function results(w) return w.env.BulwarkDB.fieldTests.results end
    local function popup(w) return FT(w):GetPopup() end
    local function asking(w)
        local p, id = popup(w)
        return p and p:IsShown() and id or nil
    end
    local function answer(w, i) select(1, popup(w)).answers[i]:Click() end
    -- a test-only question that is ready at once (the real any-time ones were confirmed and removed)
    local function pageTest(s)
        FT(s):Define{ id = "zz-page", kind = "ask", title = "Page check", when = function() return true end,
            question = "Open the Mana break page: is it there?",
            action = { label = "Open the page", fn = function() s.env.Bulwark.Window:Open("audit", "mana") end } }
    end

    local function noSecrets(w, v, path)
        if w.env.issecretvalue(v) then return false, path end
        if type(v) == "table" then
            for k, x in pairs(v) do
                local ok, where = noSecrets(w, x, path .. "." .. tostring(k))
                if not ok then return false, where end
            end
        end
        return true
    end

    ------------------------------------------------------------------ off by default: nothing happens
    local w = t.fresh()
    t.eq(w.env.BulwarkDB.fieldTests.on, false, "field tests are off by default")
    FT(w):Saw("mana-announce", { kind = "self" })
    FT(w):Saw("bwk-summon-credit", { creature = "Servitor" })    -- an auto test would record at once
    w:Advance(60)
    t.ok(next(results(w)) == nil, "off: no results")
    t.ok(not asking(w), "off: no popup")

    ------------------------------------------------------------------ on: the any-time question comes after login
    pageTest(w)
    w:Slash("/bwk tests on")
    t.eq(w.env.BulwarkDB.fieldTests.on, true, "/bwk tests on")
    w:Advance(20)
    t.eq(asking(w), "zz-page", "first ready question: the mana break page")
    local p = popup(w)
    t.ok(p.question:GetText():find("Mana break page", 1, true), "question text shown")
    t.ok(p.action:IsShown(), "action button for this test")
    p.action:Click()
    t.ok(w.env.Bulwark.Window:IsShown(), "action opens the window")
    answer(w, 1)    -- Pass
    t.eq(results(w)["zz-page"].status, "pass", "Pass recorded")
    t.ok(results(w)["zz-page"].ctx.at ~= nil, "context recorded with the result")
    t.ok(not asking(w), "popup closed after the answer")

    ------------------------------------------------------------------ an auto fact: no popup, recorded by itself
    t.ok(results(w)["fact-raidtarget-marked"] == nil, "raid mark fact waits for the in-combat reading too")
    w:EnterCombat(); w:Advance(4); w:LeaveCombat()
    local mark = results(w)["fact-raidtarget-marked"]
    t.eq(mark and mark.status, "auto", "raid mark fact recorded after an in-combat reading")
    t.ok(not asking(w) or asking(w) ~= "fact-raidtarget-marked", "auto facts never ask")

    ------------------------------------------------------------------ Saw from feature code: the healer drinking
    local g = t.fresh(function(s)
        H.Party(s)
        s.spells[430] = "Drink"
        s.units.party1.mana = { 30, 100 }
        s.units.party1.role = "HEALER"
        s.units.party2.mana = { 100, 100 }
    end)
    pageTest(g)
    g:Slash("/bwk tests on")
    g:Slash("/bwk tests reset all")
    -- answer the any-time page question first
    g:Advance(20)
    t.eq(asking(g), "zz-page", "page question first")
    answer(g, 4)    -- Skip
    t.eq(results(g)["zz-page"].status, "skip", "Skip recorded")

    g.units.party1.auras = { H.Aura(1137, "Drink") }
    g:Fire("UNIT_AURA", "party1", { isFullUpdate = true })
    g:Advance(1)
    g:Advance(25)
    t.eq(asking(g), "mana-healer-prompt", "healer drinking -> the prompt question")
    t.ok(select(1, popup(g)).question:GetText():find("Lumen is drinking", 1, true), "question names the healer")

    -- combat hides the popup; it comes back after the fight
    g:EnterCombat()
    t.ok(not asking(g), "combat hides the popup")
    g:Advance(30)
    t.ok(not asking(g), "no popup in combat")
    g:LeaveCombat()
    g:Advance(25)
    t.eq(asking(g), "mana-healer-prompt", "asked again after combat")

    -- Later: snoozed, not asked again for a while
    answer(g, 3)
    t.ok(not asking(g), "Later closes it")
    g:Advance(120)
    t.ok(asking(g) ~= "mana-healer-prompt", "snoozed")

    -- force it back with /bwk tests ask, then Fail with a note
    g:Slash("/bwk tests ask mana-healer-prompt")
    t.eq(asking(g), "mana-healer-prompt", "/bwk tests ask shows it now")
    answer(g, 2)    -- Fail -> note mode
    p = popup(g)
    t.ok(p.note:IsShown() and not p.answers[1]:IsShown(), "Fail asks for a note")
    p.note:SetText("no % shown")
    p.save:Click()
    t.eq(results(g)["mana-healer-prompt"].status, "fail", "Fail recorded")
    t.eq(results(g)["mana-healer-prompt"].note, "no % shown", "note saved")
    t.eq(results(g)["mana-healer-prompt"].data.name, "Lumen", "data saved")

    -- the key: announcement question
    g:Slash("/bwk audit mana")
    g:Advance(25)
    local id = asking(g)
    t.eq(id, "mana-announce", "announcement -> its question")
    t.ok(select(1, popup(g)).question:GetText():find("naming Lumen", 1, true), "announcement question names the healer")
    answer(g, 1)

    -- reset brings a test back
    g:Slash("/bwk tests reset mana-announce")
    t.eq(results(g)["mana-announce"], nil, "reset clears the result")

    ------------------------------------------------------------------ boss fight: secrets cleaned, errors counted
    g.units.boss1 = { name = "Taragaman", guid = "Creature-0-1-0-1-11520-0000000009", friendly = false,
                      class = "WARRIOR", level = 63, auras = {}, threat = { true, 3, 100, 100, 100 } }
    g.restricted = true
    g:Fire("ENCOUNTER_START", 9001, "Taragaman", 1, 5)
    g:EnterCombat()
    g:Advance(4)
    g:LeaveCombat()
    g:Fire("ENCOUNTER_END", 9001, "Taragaman", 1, 5, 1, {})
    local boss = results(g)["boss-fight"]
    t.ok(boss ~= nil, "boss fight recorded")
    t.eq(boss and boss.status, "auto", "no new errors: recorded as data")
    t.eq(boss and boss.data.encounter.name, "Taragaman", "encounter name kept")
    t.ok(boss and type(boss.data.threat) == "table", "threat reading kept")

    -- Clean: secrets become "<secret>"
    t.eq(FT(g).Clean(g.newSecret("mana"), 0), "<secret>", "a secret is saved as <secret>")
    t.eq(FT(g).Clean({ a = { b = g.newSecret("x") } }, 0).a.b, "<secret>", "nested secret cleaned")

    ------------------------------------------------------------------ combat boundary: 30 pulls without the error
    for _ = 1, 30 do
        g:EnterCombat(); g:Advance(1); g:LeaveCombat(); g:Advance(1)
    end
    t.eq(results(g)["audit-combat-boundary"] and results(g)["audit-combat-boundary"].status, "pass",
        "30 pulls without the aura error: pass")

    ------------------------------------------------------------------ a broken test is recorded, not repeated
    FT(g):Define{ id = "zz-broken", kind = "auto", title = "Broken", when = function() error("boom") end }
    g:Advance(4)
    t.eq(results(g)["zz-broken"].status, "broken", "a test that errors is recorded as broken")
    t.ok(results(g)["zz-broken"].note:find("boom", 1, true), "with its error")

    ------------------------------------------------------------------ a new rev runs the test again
    FT(g):Define{ id = "zz-rev", kind = "auto", title = "Rev", rev = 1, when = function() return true end,
                  probe = function(d) d.n = 1; return true end }
    g:Advance(4)
    t.eq(results(g)["zz-rev"].rev, 1, "rev 1 recorded")
    FT(g):Define{ id = "zz-rev", kind = "auto", title = "Rev", rev = 2, when = function() return true end,
                  probe = function(d) d.n = 2; return true end }
    g:Advance(4)
    t.eq(results(g)["zz-rev"].rev, 2, "rev 2 replaces the old result")
    t.eq(results(g)["zz-rev"].data.n, 2, "with the new data")

    ------------------------------------------------------------------ nothing secret reaches SavedVariables
    local ok, where = noSecrets(g, g.env.BulwarkDB.fieldTests, "fieldTests")
    t.ok(ok, "no secret in BulwarkDB.fieldTests (" .. tostring(where) .. ")")

    ------------------------------------------------------------------ off again: popup gone, nothing asked
    g:Slash("/bwk tests ask mana-self-tile")
    g:Slash("/bwk tests off")
    t.ok(not asking(g), "off hides the popup")
    g:Advance(60)
    t.ok(not asking(g), "off: no popup")
end
