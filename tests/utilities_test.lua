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
    -- [in-game 2026-11-12] level 38, defense 209 (cap 190) vs level 41: the exact numbers the client page showed.
    r = Av.Compute(snap({ level = 38, defense = 209, dodge = 6.08, parry = 5.76, block = 10.76, known = {} }), { offset = 3 })
    near(r.table.miss, 5.16, "in-game miss"); near(r.table.dodge, 5.48, "in-game dodge")
    near(r.table.parry, 5.16, "in-game parry"); near(r.table.block, 10.16, "in-game block")
    near(r.table.crit, 4.84, "in-game crit"); near(r.table.crush, 15, "in-game crush"); near(r.table.hit, 54.2, "in-game hit")
    t.eq(r.defenseNeeded, 121, "in-game: 121 defense to crit immunity")

    -- What-if: +10 defense = +0.4 % miss/dodge/parry/block, -0.4 % crit; agility at this character's rate.
    local base = snap({ dodgePerAgi = 0.05 })
    local w = Av.Compute(Av.Apply(base, { defense = 10 }), { offset = 3 })
    near(w.total, 45.2, "+10 defense: +1.6 % total"); near(w.table.crit, 1.2, "+10 defense: crit 1.2")
    t.eq(w.defenseNeeded, 30, "+10 defense: 30 to go")
    w = Av.Compute(Av.Apply(base, { agility = 20, dodge = 1, parry = 1, block = 2 }), { offset = 3 })
    near(w.table.dodge, 13.4, "20 agility (1 %) + 1 % dodge"); near(w.table.parry, 11.4, "+1 parry")
    near(w.table.block, 15.4, "+2 block")
    w = Av.Compute(Av.Apply(snap({ parry = 0 }), { defense = 10, parry = 5 }), { offset = 3 })
    near(w.table.parry, 0, "no parry stays no parry")
    t.eq(base.defense, 400, "Apply doesn't change the snapshot")

    -- Snapshot from the game: shield in the off hand, Shield Block known.
    sim.stats = { defense = 400, defenseMod = 0, dodge = 12, parry = 11, block = 14, shieldBlock = 30, dodgeFromAgi = 0.05,
                  attributes = { [2] = 100 } }
    sim.equipped[17] = "|cffffffff|Hitem:4975:::::::::|h[Vigilant Buckler]|h|r"
    sim.itemInfo[4975] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
    sim.known[2565] = true
    local s = Av.Read()
    t.ok(s, "snapshot out of combat")
    t.eq(s.defense, 400, "defense = base + modifier"); t.ok(s.hasShield, "shield detected")
    t.ok(s.known.shieldBlock and not s.known.holyShield, "warrior knows Shield Block only")
    near(s.dodgePerAgi, 0.05, "5 % dodge from 100 agility = 0.05 % each")

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

    -- What-if page: sliders change the right column only; Reset puts them back.
    NS.Window:Select("utilities", "whatif")
    local wi = NS:GetArea("utilities").pages[2]
    t.ok(wi.frame and wi.frame:IsShown(), "What-if page built and shown")
    t.eq(wi.rows.total.value:GetText(), "61.60  >  61.60%", "no change yet")
    t.eq(wi.rows.total.change:GetText(), "", "no change shown")
    wi.sliders.defense:SetValue(40)
    t.eq(wi.rows.total.value:GetText(), "61.60  >  68.00%", "+40 defense: +6.4 % total")
    t.eq(wi.rows.total.change:GetText(), "+6.40", "change shown")
    t.ok(wi.verdictCrit:GetText():find("Crit immune", 1, true), "440 defense: crit immune")
    t.eq(wi.rows.crit.change:GetText(), "-1.60", "crit change")
    wi.sliders.agility:SetValue(20)
    t.eq(wi.rows.dodge.value:GetText(), "29.40  >  32.00%", "+40 def +20 agi: +1.6 + 1.0 dodge (sheet 30 - 0.6)")
    wi.reset:Click()
    t.eq(wi.rows.total.change:GetText(), "", "Reset clears the changes")
    -- Past 100 %: block shrinks because dodge etc. grew. Shown grey, not as a loss ([in-game] -15.55 was orange).
    NS.db.utilities.count.shieldBlock = true
    wi.sliders.dodge:SetValue(5)
    local text, r, g, b = wi.rows.block.change:GetText(), wi.rows.block.change:GetTextColor()
    t.eq(text, "-5.00", "block pushed off the table by +5 dodge")
    local muted = NS.Kit.C.muted
    t.ok(r == muted[1] and g == muted[2] and b == muted[3], "capped block change is grey")
    r, g, b = wi.rows.dodge.change:GetTextColor()
    t.ok(g > r, "dodge gain is green")
    wi.reset:Click()
    NS.db.utilities.count.shieldBlock = false

    -- Command prints the same table.
    local before = #sim.output
    sim:Slash("/bwk utilities avoid")
    t.ok(#sim.output > before, "/bwk utilities avoid prints")
    t.eq(#sim.errors, 0, "no Lua errors")
end
