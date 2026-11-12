-- Gear audit, step 4: the on-screen mats tracker (Enchant list mats, greyed out once there are enough).
return function(sim, t)
    local NS = sim.env.Bulwark
    local Gear, Tracker = NS.GearAudit, NS.MatsTracker
    local function link(id, enchant) return "|cffffffff|Hitem:" .. id .. ":" .. (enchant or "") .. ":::::::60|h[x]|h|r" end
    sim.equipped = { [9] = link(101), [15] = link(102) }
    local names = { [14344] = "Large Brilliant Shard", [20725] = "Nexus Crystal", [12809] = "Guardian Stone" }
    sim.env.C_Item.GetItemNameByID = function(id) return names[id] end

    local frame = sim.env.BulwarkMatsTracker
    t.ok(frame, "tracker frame created at login")
    t.ok(not frame:IsShown(), "hidden until turned on")

    -- Current gear (no saved sets): Superior Deflection on the bracers, Cloak - Dodge on the cloak
    Gear.SetPick(Gear.WORN, 9, 1248665)
    Gear.SetPick(Gear.WORN, 15, 25086)
    Tracker:SetShown(true)
    t.ok(frame:IsShown(), "shown once turned on with picks to do")
    local function text(i) return Tracker.lines[i] and Tracker.lines[i]:IsShown() and Tracker.lines[i].text:GetText() end
    -- Best quality first: Nexus Crystal (epic), Large Brilliant Shard (rare), Guardian Stone (uncommon)
    t.eq(text(1), "0/3 Nexus Crystal", "epic first")
    t.eq(text(2), "0/11 Large Brilliant Shard", "then rare; shards summed (3 + 8)")
    t.eq(text(3), "0/8 Guardian Stone", "then uncommon")
    t.ok(not text(4), "three lines")

    -- Enough shards: the line greys out with the tick and keeps its place (same order as the Enchant list)
    sim.items[14344] = 14
    Tracker:Refresh()
    t.eq(text(2), "11/11 Large Brilliant Shard", "done line capped at need, in place")
    t.ok(Tracker.lines[2].tick:IsShown() and not Tracker.lines[1].tick:IsShown(), "tick only on the done line")
    sim.items[20725], sim.items[12809] = 3, 8
    Tracker:Refresh()
    t.eq(frame.note:GetText(), "All mats ready.", "all ready note")

    -- Enchants applied: nothing left to do, the tracker hides itself
    sim.equipped[9] = link(101, 8214)
    sim.equipped[15] = link(102, 2622)
    Tracker:Refresh()
    t.ok(not frame:IsShown(), "hidden when every pick is done")
    t.eq(NS.char.gear.tracker.shown, true, "but stays turned on")

    -- Slash command toggles it; Enchant list page button too
    sim:Slash("/bwk utilities tracker")
    t.eq(NS.char.gear.tracker.shown, false, "/bwk utilities tracker: off")
    sim:Slash("/bwk utilities tracker reset")
    t.eq(NS.char.gear.tracker.shown, true, "reset turns it on")
    t.eq(NS.char.gear.tracker.x, nil, "reset clears the position")
    sim:Slash("/bwk")
    NS.Window:Select("utilities", "enchantlist")
    local page
    for _, p in ipairs(NS:GetArea("utilities").pages) do if p.key == "enchantlist" then page = p end end
    t.eq(page.track:GetLabel(), "Stop tracking", "button label follows the setting")
    -- Enchant list mats: same order as the tracker
    Gear.SetPick(Gear.WORN, 9, 1248665)   -- picks are done (enchanted): add an open one again
    sim.equipped[15] = link(102)
    page:refresh()
    local order = {}
    for _, row in ipairs(page.mats.rows) do if row:IsShown() then order[#order + 1] = row.data.item end end
    t.eq(table.concat(order, ","), "20725,14344,12809", "Enchant list: epic, rare, uncommon (as the tracker)")
    page.track:Click()
    t.eq(NS.char.gear.tracker.shown, false, "button turns it off")
    t.eq(page.track:GetLabel(), "Track on screen", "label updated")
end
