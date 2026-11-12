-- Utilities area, step 1: the Avoidance calculator (math, snapshot, page, combat freeze, command).
-- Expected numbers: kb/addons/Bulwark-Utilities.md (worked example) and the in-game checks of 2026-11-12.
return function(sim, t)
    local NS = sim.env.Bulwark
    local Av = NS.Avoidance
    local function near(a, b, msg)
        t.ok(type(a) == "number" and math.abs(a - b) < 0.001, (msg or "number") .. ": expected " .. b .. ", got " .. tostring(a))
    end
    local function snap(over)
        local s = { level = 60, defense = 400, dodge = 12, parry = 11, block = 14, hasShield = true,
                    known = { shieldBlock = true }, active = {} }
        for k, v in pairs(over or {}) do s[k] = v end
        return s
    end

    t.ok(NS:IsAreaRunning("utilities"), "Utilities runs at login")
    t.eq(NS.db.utilities.mobOffset, 3, "default attacker: boss (+3)")

    -- Worked example vs a boss: sheet values minus 0.6 each, miss from defense, crit 1.6, crush 15.
    local r = Av.Compute(snap(), { offset = 3 })
    near(r.table.miss, 8.4, "miss"); near(r.table.dodge, 11.4, "dodge"); near(r.table.parry, 10.4, "parry")
    near(r.table.block, 13.4, "block"); near(r.total, 43.6, "total"); near(r.table.crit, 1.6, "crit")
    near(r.table.crush, 15, "crush"); near(r.table.hit, 39.8, "hit")
    t.ok(r.canCrush and not r.uncrushable, "a boss can crush; not uncrushable")
    near(r.short, 56.4, "short of 100 %")
    t.ok(not r.critImmune, "can be crit at 400 defense")
    t.eq(r.defenseNeeded, 40, "440 defense = crit immune vs a boss")

    -- Shield Block counted: block takes what's left of the roll, crits and crushes are gone.
    r = Av.Compute(snap(), { offset = 3, count = { shieldBlock = true } })
    near(r.table.block, 69.8, "block capped by the table")
    near(r.table.crit, 0, "no crits"); near(r.table.crush, 0, "no crushes"); near(r.table.hit, 0, "no hits")
    t.ok(r.uncrushable, "uncrushable with Shield Block")
    t.eq(#r.counted, 1, "Shield Block listed as counted")
    -- Already active (sheet includes the +75 [in-game]) but not ticked: taken out again.
    r = Av.Compute(snap({ block = 89, active = { shieldBlock = true } }), { offset = 3 })
    near(r.table.block, 13.4, "active Shield Block not counted unless ticked")
    -- Ticked and active: counted once.
    r = Av.Compute(snap({ block = 89, active = { shieldBlock = true } }), { offset = 3, count = { shieldBlock = true } })
    near(r.raw.block, 88.4, "active + ticked counted once")
    -- Not learned: the tick does nothing.
    r = Av.Compute(snap({ known = {} }), { offset = 3, count = { shieldBlock = true } })
    near(r.table.block, 13.4, "unknown cooldown ignored")

    -- Defense: crit immune at 440; extra defense doesn't lower crushing blows.
    r = Av.Compute(snap({ defense = 440 }), { offset = 3 })
    t.ok(r.critImmune, "crit immune at 440"); t.eq(r.defenseNeeded, 0, "no defense needed")
    near(r.raw.crush, 15, "crush stays 15 % above the defense cap")
    -- Lower attackers: +2 can't crush a capped tank; same level: no penalty.
    r = Av.Compute(snap(), { offset = 2 })
    t.ok(not r.canCrush, "+2 mob can't crush at capped defense")
    near(r.table.dodge, 11.6, "+2: 0.4 % penalty")
    r = Av.Compute(snap(), { offset = 0 })
    near(r.table.dodge, 12, "same level: sheet value")
    -- Unleveled defense skill: a +2 mob crushes.
    r = Av.Compute(snap({ defense = 295 }), { offset = 2 })
    t.ok(r.canCrush, "defense skill below the cap: +2 mob can crush")
    near(r.raw.crush, 15, "gap 15 -> 15 %")
    -- No shield: no block, cooldown ignored.
    r = Av.Compute(snap({ hasShield = false }), { offset = 3, count = { shieldBlock = true } })
    near(r.table.block, 0, "no shield, no block")
    -- The in-game sample (level 42, defense 209/210) vs a +3 mob.
    r = Av.Compute(snap({ level = 42, defense = 209, dodge = 6.08, parry = 5.76, block = 10.76 }), { offset = 3 })
    near(r.table.miss, 4.36, "level-42 miss"); near(r.table.dodge, 5.48, "level-42 dodge")

    -- Snapshot from the game: shield in the off hand, Shield Block known.
    sim.stats = { defense = 400, defenseMod = 0, dodge = 12, parry = 11, block = 14, shieldBlock = 30, dodgeFromAgi = 0.05 }
    sim.equipped[17] = "|cffffffff|Hitem:4975:::::::::|h[Vigilant Buckler]|h|r"
    sim.itemInfo[4975] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
    sim.known[2565] = true
    local s = Av.Read()
    t.ok(s, "snapshot out of combat")
    t.eq(s.defense, 400, "defense = base + modifier"); t.ok(s.hasShield, "shield detected")
    t.ok(s.known.shieldBlock and not s.known.holyShield, "warrior knows Shield Block only")

    -- Page shows the table and verdicts.
    sim:Slash("/bwk")
    NS.Window:Select("utilities", "avoidance")
    local page = NS:GetArea("utilities").pages[1]
    t.ok(page.frame and page.frame:IsShown(), "Avoidance page built and shown")
    t.eq(page.rows.total.value:GetText(), "43.60%", "total on the page")
    t.eq(page.rows.crush.value:GetText(), "15.00%", "crush on the page")
    t.ok(page.verdictCrush:GetText():find("Crushable", 1, true), "crushable verdict")
    t.ok(page.verdictCrit:GetText():find("40 more defense", 1, true), "crit verdict: " .. page.verdictCrit:GetText())
    t.ok(page.count:IsShown(), "Shield Block tick shown")
    page.count:Click()
    t.eq(NS.db.utilities.count.shieldBlock, true, "tick saved")
    t.ok(page.verdictCrush:GetText():find("Only while Shield Block lasts", 1, true), "uncrushable only while it lasts")
    page.count:Click()
    page.levels[2]:Click()
    t.eq(NS.db.utilities.mobOffset, 2, "attacker level saved")
    t.ok(page.verdictCrush:GetText():find("can't land crushing", 1, true), "+2: no crushing blows")
    page.levels[3]:Click()

    -- Combat: the game hides the stats; the page keeps the last values and says so.
    sim:EnterCombat()
    t.eq(Av.Read(), nil, "no snapshot while stats are secret")
    sim.stats.dodge = 30
    sim:Fire("UNIT_AURA", "player")
    sim:Advance(0.5)
    page:refresh()
    t.eq(page.rows.total.value:GetText(), "43.60%", "last values kept in combat")
    t.ok(page.frozen:GetText() ~= "", "frozen note shown")
    sim:LeaveCombat()
    sim:Advance(0.5)
    t.eq(page.rows.total.value:GetText(), "61.60%", "fresh values after combat (event-driven refresh)")
    t.eq(page.frozen:GetText(), "", "frozen note gone")

    -- Command prints the same table.
    local before = #sim.output
    sim:Slash("/bwk utilities avoid")
    t.ok(#sim.output > before, "/bwk utilities avoid prints")
    t.eq(#sim.errors, 0, "no Lua errors")
end
