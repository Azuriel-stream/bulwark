local ADDON_NAME, NS = ...

-- Optional Auctionator support for the Enchant list (kb/addons/Bulwark-Utilities.md "Auctionator"): prices for the
-- mats and a shopping list. Bulwark never needs Auctionator: without it every function here returns nil/false and
-- the pages hide the price column and the button. Only Auctionator's public API (Auctionator.API.v1) is used, every
-- call under pcall (it raises errors on bad arguments, and its database may not be ready yet).

local AH = {}
NS.AuctionHouse = AH

AH.CALLER = "Bulwark"                 -- Auctionator's callerID: the add-on name
AH.LIST_NAME = "Bulwark Enchants"     -- shopping list name in Auctionator (replaced on every send)

local function API()
    local a = rawget(_G, "Auctionator")
    a = type(a) == "table" and type(a.API) == "table" and a.API.v1
    return type(a) == "table" and a or nil
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, AH.CALLER, ...)
    if ok then return v end
    return nil
end

function AH.Available()
    local a = API()
    return a ~= nil and type(a.GetAuctionPriceByItemID) == "function"
end

function AH.CanSend()
    local a = API()
    return a ~= nil and type(a.CreateShoppingList) == "function" and type(a.ConvertToSearchString) == "function"
end

-- Unit price in copper and where it comes from: the cheaper of a vendor that sells it ("vendor", Auctionator notes
-- merchant prices when you visit one) and the last auction house scan ("auction"). nil = no price known.
function AH.Price(itemID)
    local a = API()
    if not a then return nil end
    local auction = Call(a.GetAuctionPriceByItemID, itemID)
    local vendor = Call(a.GetVendorPriceByItemID, itemID)
    auction = type(auction) == "number" and auction > 0 and auction or nil
    vendor = type(vendor) == "number" and vendor > 0 and vendor or nil
    if vendor and (not auction or vendor <= auction) then return vendor, "vendor" end
    if auction then return auction, "auction" end
    return nil
end

-- Days since the item was last seen on the auction house (Auctionator: nil after 21 days or never).
function AH.Age(itemID)
    local a = API()
    return a and Call(a.GetAuctionAgeByItemID, itemID) or nil
end

-- Cost of a list { { item = id, n = count } }: total copper of the priced ones, how many had no price.
function AH.Cost(list)
    local total, unknown = 0, 0
    for _, e in ipairs(list) do
        if (e.n or 0) > 0 then
            local p = AH.Price(e.item)
            if p then total = total + p * e.n else unknown = unknown + 1 end
        end
    end
    return total, unknown
end

-- "12g 34s" (rounded to silver above 1 gold, so long totals stay readable); the client's coin icons when it has them.
function AH.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    if copper >= 10000 then copper = math.floor(copper / 100 + 0.5) * 100 end
    local fmt = rawget(_G, "GetMoneyString")
    if type(fmt) == "function" then
        local ok, s = pcall(fmt, copper, true)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Shopping list of what is still missing: list = { { item, n } } (n = amount to buy; 0 or less is left out).
-- Exact-name searches with the amount. Returns sent (count) and skipped (names not loaded yet) or nil when Auctionator
-- refused it. The list "Bulwark Enchants" is replaced each time.
function AH.SendList(list, nameOf)
    local a = API()
    if not (a and AH.CanSend()) then return nil end
    local terms, skipped = {}, 0
    for _, e in ipairs(list) do
        if (e.n or 0) > 0 then
            local name = nameOf(e.item)
            local s = name and Call(a.ConvertToSearchString, { searchString = name, isExact = true, quantity = e.n })
            if type(s) == "string" then terms[#terms + 1] = s else skipped = skipped + 1 end
        end
    end
    if #terms == 0 then return 0, skipped end
    local ok = pcall(a.CreateShoppingList, AH.CALLER, AH.LIST_NAME, terms)
    if not ok then return nil end
    return #terms, skipped
end
