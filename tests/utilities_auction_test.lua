-- Enchant list + Auctionator (optional): mat prices, cost of what's missing, shopping list. Without Auctionator the
-- page looks exactly as before.
return function(sim, t)
    local NS = sim.env.Bulwark
    local Gear, AH = NS.GearAudit, NS.AuctionHouse
    local function link(id, enchant) return "|cffffffff|Hitem:" .. id .. ":" .. (enchant or "") .. ":::::::60|h[x]|h|r" end
    sim.equipped = { [9] = link(101), [15] = link(102) }
    local names = { [14344] = "Large Brilliant Shard", [20725] = "Nexus Crystal", [12809] = "Guardian Stone" }
    sim.env.C_Item.GetItemNameByID = function(id) return names[id] end
    sim.env.GetMoneyString = nil          -- plain "12g 34s" text (the client uses its coin icons)

    -- Superior Deflection (3 shards) + Cloak - Dodge (3 Nexus Crystal, 8 shards, 8 Guardian Stone)
    Gear.SetPick(Gear.WORN, 9, 1248665)
    Gear.SetPick(Gear.WORN, 15, 25086)
    sim.items[14344] = 2                  -- have 2 of 11 shards: 9 to buy

    sim:Slash("/bwk")
    NS.Window:Select("utilities", "enchantlist")
    local page
    for _, p in ipairs(NS:GetArea("utilities").pages) do if p.key == "enchantlist" then page = p end end
    local function row(item)
        for _, r in ipairs(page.mats.rows) do if r:IsShown() and r.data.item == item then return r end end
    end

    -- 1. No Auctionator: no prices, no button, card as before
    t.ok(not AH.Available(), "no Auctionator")
    page:refresh()
    t.ok(not page.send:IsShown() and not page.total:IsShown() and not page.colPrice:IsShown(), "footer hidden")
    t.eq(row(14344).price:GetText(), "", "no price column")
    local baseHeight = page.matsCard:GetHeight()

    -- 2. Auctionator with prices: shards 5g at auction; Guardian Stone 30s at auction but 20s at a vendor;
    --    Nexus Crystal never seen
    local lists, calls = {}, {}
    local prices = { [14344] = 50000, [12809] = 3000 }
    local vendor = { [12809] = 2000 }
    local api = {
        GetAuctionPriceByItemID = function(caller, id) calls[#calls + 1] = caller; return prices[id] end,
        GetVendorPriceByItemID = function(_, id) return vendor[id] end,
        GetAuctionAgeByItemID = function(_, id) return prices[id] and 2 or nil end,
        ConvertToSearchString = function(_, term)
            return string.format('"%s";;;;;;;;;;;;;%d', term.searchString, term.quantity) .. (term.isExact and "" or "?")
        end,
        CreateShoppingList = function(_, name, terms) lists[name] = terms end,
    }
    sim.env.Auctionator = { API = { v1 = api } }
    t.ok(AH.Available() and AH.CanSend(), "Auctionator found")
    t.eq(select(2, AH.Price(12809)), "vendor", "cheaper vendor price wins")
    t.eq(AH.Price(12809), 2000, "vendor price")
    t.eq(AH.Price(20725), nil, "unknown price")
    t.eq(AH.Money(4512345), "451g 23s", "money rounded to silver above 1g")
    t.eq(AH.Money(250), "2s 50c", "small amounts keep copper")

    page:refresh()
    t.eq(calls[1], "Bulwark", "caller ID is the add-on name")
    t.ok(page.send:IsShown() and page.total:IsShown(), "footer shown")
    t.ok(page.matsCard:GetHeight() > baseHeight, "card grows for the footer")
    -- [in-game] the header sat squeezed above row 1: it has its own line now, the rows start below it
    t.ok(page.colPrice:IsShown() and page.colHave:IsShown(), "column headers shown")
    t.eq(select(3, page.mats.rows[1]:GetPoint()), -38 - 18, "first row below the header line")
    t.eq(row(14344).price:GetText(), "45g", "9 missing shards x 5g")
    t.eq(row(12809).price:GetText(), "1g 60s", "8 Guardian Stones x 20s (vendor)")
    t.eq(row(20725).price:GetText(), "no price", "unpriced mat")
    t.eq(page.total:GetText(), "To buy: 46g 60s  (1 without a price)", "total of what's missing")

    -- 3. Send: only the missing amounts, exact names, the list replaced each time
    page.send:Click()
    local terms = lists[AH.LIST_NAME]
    t.eq(terms and #terms, 3, "three mats on the list")
    t.eq(table.concat(terms, "|"), '"Nexus Crystal";;;;;;;;;;;;;3|"Large Brilliant Shard";;;;;;;;;;;;;9|"Guardian Stone";;;;;;;;;;;;;8',
        "exact searches with the missing amount, Enchant list order")
    t.ok(sim.output[#sim.output]:find("3 mats sent", 1, true), "chat note: " .. tostring(sim.output[#sim.output]))

    -- A name not loaded yet is left out and reported
    names[20725] = nil
    page:sendList()
    t.eq(#lists[AH.LIST_NAME], 2, "unloaded name left out")
    t.ok(sim.output[#sim.output]:find("1 left out", 1, true), "reported: " .. tostring(sim.output[#sim.output]))
    names[20725] = "Nexus Crystal"

    -- Auctionator refuses (raises an error): no Lua error for us, a chat note instead
    api.CreateShoppingList = function() error("ListManager not ready") end
    page:sendList()
    t.ok(sim.output[#sim.output]:find("didn't take the list", 1, true), "refusal reported")

    -- 4. Everything in the bags: nothing to buy, button greyed
    sim.items[14344], sim.items[20725], sim.items[12809] = 11, 3, 8
    page:refresh()
    t.eq(page.total:GetText(), "Nothing to buy: you have every mat.", "nothing to buy")
    t.ok(not page.send:IsEnabled(), "send button greyed")
    t.eq(row(14344).price:GetText(), "", "no cost when you have enough")

    -- 5. Cost of one enchant (picker tooltip): Superior Deflection = 3 shards = 15g; unpriced counted apart
    t.eq((AH.Cost({ { item = 14344, n = 3 } })), 150000, "3 shards = 15g")
    t.eq(select(2, AH.Cost({ { item = 14344, n = 3 }, { item = 20725, n = 1 } })), 1, "one without a price")

    -- 6. Auctionator unloaded again (e.g. disabled): back to the plain page
    sim.env.Auctionator = nil
    page:refresh()
    t.ok(not page.send:IsShown() and not page.total:IsShown(), "footer hidden again")
    t.eq(page.matsCard:GetHeight(), baseHeight, "card back to its size")
    t.ok(not page.colPrice:IsShown() and not page.colHave:IsShown(), "no headers")
    t.eq(select(3, page.mats.rows[1]:GetPoint()), -38, "rows back at the top")
end
