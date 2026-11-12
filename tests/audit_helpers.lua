-- Shared setup for Bulwark Audit tests (require("audit_helpers")); from TankAuditForever tests/helpers.lua.
local H = {}

H.SPELLS = {
    [6673] = "Battle Shout", [71] = "Defensive Stance", [25780] = "Righteous Fury",
    [1243] = "Power Word: Fortitude", [14752] = "Divine Spirit", [20217] = "Blessing of Kings",
    [19740] = "Blessing of Might", [19977] = "Blessing of Light", [19742] = "Blessing of Wisdom",
    [465] = "Devotion Aura", [1038] = "Blessing of Salvation", [4987] = "Cleanse", [1126] = "Mark of the Wild",
}

-- Party: player + priest (party1) + paladin (party2)
function H.Party(sim)
    for id, name in pairs(H.SPELLS) do sim.spells[id] = name end
    sim.units.party2 = { name = "Aldric", surname = "Dawnward", class = "PALADIN", guid = "Player-1-00000003",
                         friendly = true, level = 60, auras = {} }
    sim.group = "party"
    -- a tank's shield (else the gear check shows "No shield" in Defensive Stance)
    sim.equipped[17] = "|cffffffff|Hitem:4975::::::::|h[Vigilant Buckler]|h|r"
    sim.itemInfo[4975] = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }
end

function H.Aura(spellId, name, opts)
    local a = { spellId = spellId, name = name, icon = 136000, expirationTime = 0, duration = 0 }
    for k, v in pairs(opts or {}) do a[k] = v end
    return a
end

-- Replan and let the coalescing timer fire
function H.Rescan(sim)
    sim:Fire("UNIT_AURA", "player", { isFullUpdate = true })
    sim:Advance(1)
end

-- Tiles the player can see: shown AND not transparent (buffs that are up wait invisibly at alpha 0)
function H.Shown(sim)
    local out = {}
    for _, tile in ipairs(sim.env.Bulwark.AuditBar:GetTiles()) do
        if tile:IsShown() and tile:GetAlpha() > 0 and tile.item then out[#out + 1] = tile end
    end
    return out
end

-- A planned tile whether visible or waiting invisibly
function H.Planned(sim, tileKey)
    for _, tile in ipairs(sim.env.Bulwark.AuditBar:GetTiles()) do
        if tile:IsShown() and tile.item and tile.item.tileKey == tileKey then return tile end
    end
end

function H.Find(sim, tileKey)
    for _, tile in ipairs(H.Shown(sim)) do
        if tile.item.tileKey == tileKey then return tile end
    end
end

function H.Keys(sim)
    local out = {}
    for _, tile in ipairs(H.Shown(sim)) do out[#out + 1] = tile.item.tileKey end
    return table.concat(out, ", ")
end

-- The Blizzard aura container created for a tile (or holder)
function H.Container(sim, parent)
    for _, f in ipairs(sim.frames) do
        if f._type == "AuraContainer" and f._parent == parent then return f end
    end
end

return H
