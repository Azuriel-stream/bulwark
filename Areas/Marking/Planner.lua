local ADDON_NAME, NS = ...
local MK = NS.Marking

-- Pack planner: decides which icon each visible mob gets, out of combat. Port of legacy DecidePull
-- (Core/TankMark_Pull.lua v0.32): fixed icons, then the kill ladder by priority, then CC on the leftovers.
-- Knowledge per mob: learned by name (open world) > learned by signature (instances) > rules (power type x tier).
local Planner = MK:RegisterModule("Planner")
local Rules, Utils = MK.Rules, MK.Utils

Planner.plan = { entries = {}, killOrder = {}, overflow = {}, reserved = {} }

-- =========================================================================
-- Pure part (no WoW API): tests drive these directly.
-- =========================================================================
function Planner.Knowledge(rec, zoneMobs)
    if zoneMobs then
        local e = rec.name and zoneMobs.names[rec.name]
        if e then return e, "name" end
        e = zoneMobs.sigs[rec.sig] or (rec.sigBase and zoneMobs.sigs[rec.sigBase])
        if e then return e, "sig" end
    end
    return nil, "rules"
end

-- recs: plate records; zoneMobs: { names, sigs } or nil
-- ctx: { ladder = {icons in kill order}, ccSlots = {...}, reserved = {[icon] = true} }
-- returns { entries = { {rec, icon, reason, role, prio, source} } in icon-assignment order,
--           killOrder = { token, ... } (kill-marked mobs, kill-first), overflow = { rec, ... } }
function Planner.Build(recs, zoneMobs, ctx)
    local used = {}
    for icon in pairs(ctx.reserved or {}) do used[icon] = true end
    local slots = {}
    for _, s in ipairs(ctx.ccSlots or {}) do
        table.insert(slots, { mark = s.mark, class = s.class, race = s.race, alive = s.alive,
                              used = s.used or used[s.mark], disabled = s.disabled })
    end
    local hasCC = #slots > 0

    local pack = {}
    for _, rec in ipairs(recs) do
        local k, source = Planner.Knowledge(rec, zoneMobs)
        if not (k and k.type == "IGNORE") then
            local role = (k and k.role) or Rules.RoleFromPower(rec.power)
            table.insert(pack, {
                rec = rec, role = role, source = source,
                prio = (k and tonumber(k.prio)) or Rules.RoleTierPrio(role, rec.tier),
                fixed = k and tonumber(k.icon),
                authoredCC = (k and k.type == "CC") or false,
                authoredClass = k and k.class,
            })
        end
    end

    local entries, killOrder, overflow = {}, {}, {}
    local function assign(c, icon, reason)
        c.icon, c.reason = icon, reason
        used[icon] = true
        table.insert(entries, { rec = c.rec, icon = icon, reason = reason, role = c.role, prio = c.prio,
                                source = c.source })
    end

    -- Kill-first order: priority, then the Shift-hover order (so an equal mob hovered later never takes the
    -- skull), else lower level (dies faster), then the order the plates appeared (deterministic).
    table.sort(pack, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        local pa, pb = tonumber(a.rec.pick), tonumber(b.rec.pick)
        if pa and pb and pa ~= pb then return pa < pb end
        if a.rec.level ~= b.rec.level then return a.rec.level < b.rec.level end
        return a.rec.seq < b.rec.seq
    end)

    -- 0. Fixed icons the player taught ("this mob is always moon").
    for _, c in ipairs(pack) do
        if c.fixed and c.fixed >= 1 and c.fixed <= 8 and not used[c.fixed] then
            assign(c, c.fixed, c.authoredCC and "cc" or "fixed")
        end
    end

    -- 1. Kill pass down the ladder. Authored CC mobs wait for the CC pass when there are CC slots.
    local li = 1
    local function NextLadderIcon()
        while li <= #ctx.ladder do
            local candidate = ctx.ladder[li]
            li = li + 1
            if not used[candidate] then return candidate end
        end
    end
    for _, c in ipairs(pack) do
        if not c.icon and not (c.authoredCC and hasCC) then
            local icon = NextLadderIcon()
            if not icon then break end
            assign(c, icon, "kill")
        end
    end

    -- 2. CC pass on the leftovers, kill-last first (legacy ADR 0002: prio decides, CC the tail).
    local ccCands = {}
    for _, c in ipairs(pack) do
        if not c.icon and Rules.CCTierEligible(c.rec.tier)
            and (c.authoredCC or Rules.MeetsAutoCCFloor(c.role, c.rec.tier)) then
            table.insert(ccCands, c)
        end
    end
    for i = #ccCands, 1, -1 do
        local c = ccCands[i]
        local mark = Rules.SelectCCSlot(c.authoredClass, c.rec.ctype, slots, c.authoredCC, c.rec.immune)
        if mark and not used[mark] then
            for _, s in ipairs(slots) do
                if s.mark == mark then s.used = true end
            end
            assign(c, mark, "cc")
        end
    end

    -- 3. A CC mob that no CC mark fits (slot taken, CC illegal on its type, immune) still dies: next tank mark.
    for _, c in ipairs(pack) do
        if not c.icon and c.authoredCC then
            local icon = NextLadderIcon()
            if not icon then break end
            assign(c, icon, "cc-fallback")
        end
    end
    for _, c in ipairs(pack) do
        if c.reason == "kill" or c.reason == "fixed" or c.reason == "cc-fallback" then
            table.insert(killOrder, c.rec.token)
        end
    end

    -- 4. Never drop silently.
    for _, c in ipairs(pack) do
        if not c.icon then table.insert(overflow, c.rec) end
    end
    return { entries = entries, killOrder = killOrder, overflow = overflow, reserved = ctx.reserved or {} }
end

-- =========================================================================
-- Shell: reads the world, rebuilds out of combat, tells Marker/Overlay.
-- =========================================================================

-- Icons already on some mob. GetNextAvailableRaidTargetMarkerIndex was readable in the open world and in a
-- dungeon (run 3); icons on dead mobs count as free (its treatDeadNonFriendlyAsAvailable flag). Plus: plates that
-- visibly carry an icon keep it. Also returns the icons only corpses wear (taken without the flag, free with it), so
-- /bwk mark plan shows the flag at work.
local function IconTaken(icon, deadAreFree)
    local ok, nextFree = pcall(GetNextAvailableRaidTargetMarkerIndex, icon, false, false, deadAreFree)
    return ok and not Utils.IsSecret(nextFree) and type(nextFree) == "number" and nextFree ~= icon
end

-- Icons this client put on a mob ([icon] = plate record), from every SetRaidTarget that runs here: MK's keys
-- (Blizzard's secure raidtarget action calls it) and the player's own marking. Needed because the client keeps an
-- icon "taken" once the corpse it sits on is out of range or despawned: the dead-mob flag above can't see that
-- corpse any more [in-game 2026-10-16: skull stuck after a kill]. An icon we saw go on a mob that died is free.
-- Marks set by other group members don't pass here; theirs stay reserved.
Planner.placed = {}

local function OnSetRaidTarget(unit, icon)
    if Utils.IsSecret(unit) or Utils.IsSecret(icon) or type(icon) ~= "number" then return end
    local ok, rec = pcall(MK.Plates.RecordFor, MK.Plates, unit)
    rec = ok and rec or nil
    if icon == 0 then
        for i, r in pairs(Planner.placed) do
            if r == rec then Planner.placed[i] = nil end
        end
    elseif icon >= 1 and icon <= 8 then
        Planner.placed[icon] = rec or false   -- false: not a mob with a plate (a player, a far unit): never freed here
    end
    MK:Debug("mark %d on %s (%s)", icon, tostring(unit), rec and "plate known" or "no plate")
end

-- The icon this client put on a plate record, or nil (debug trace).
function Planner.MarkOf(rec)
    for icon, r in pairs(Planner.placed) do
        if r == rec then return icon end
    end
    return nil
end

local function PlacedOnCorpse(icon)
    local rec = Planner.placed[icon]
    return rec and rec.dead or false
end

-- Solo, only this client sets marks. A taken icon no visible mob can be wearing sits on a corpse the client lost
-- or on a mob out of sight: free to reuse. Kept: icons we put on a living mob whose plate is still shown, and every
-- unknown icon while a visible marked mob's icon is unaccounted for (its icon itself is secret). [2026-10-16: a skull
-- stuck from before a /reload, which the placed list can't know about]
local function SoloStale(taken)
    if IsInGroup() then return {} end
    local Plates, known, onPlates = MK.Plates, {}, 0
    for token, rec in pairs(Plates.records) do
        if not rec.dead and not rec.player and Plates:IsMarked(token) then onPlates = onPlates + 1 end
    end
    for icon in pairs(taken) do
        local rec = Planner.placed[icon]
        if rec and not rec.dead and Plates.records[rec.token] == rec then known[icon] = true end
    end
    local nKnown = 0
    for _ in pairs(known) do nKnown = nKnown + 1 end
    local stale = {}
    if onPlates > nKnown then return stale end
    for icon in pairs(taken) do
        if not known[icon] then stale[icon] = true end
    end
    return stale
end

local function ReservedIcons()
    local reserved, onCorpses, stale = {}, {}, {}
    if GetNextAvailableRaidTargetMarkerIndex then
        for icon = 1, 8 do
            if IconTaken(icon, true) then
                if PlacedOnCorpse(icon) then onCorpses[icon] = true else reserved[icon] = true end
            elseif IconTaken(icon, false) then
                onCorpses[icon] = true
            end
        end
        stale = SoloStale(reserved)
        for icon in pairs(stale) do reserved[icon] = nil end
    end
    return reserved, onCorpses, stale
end

function Planner:Rebuild()
    if InCombatLockdown() then return end
    local Plates = MK.Plates
    local recs = {}
    local candidates, skipped = Plates:GetCandidates()
    for _, rec in ipairs(candidates) do
        if Plates:IsMarked(rec.token) then
            table.insert(skipped, { rec = rec, reason = "SKIP_MARKED" })
        else
            table.insert(recs, rec)
        end
    end
    local zoneMobs = MK.db.mobs[Plates.zone]
    local reserved, onCorpses, stale = ReservedIcons()
    for icon in pairs(MK.Team:FollowIcons()) do reserved[icon] = true; stale[icon] = nil end   -- a fixed icon must never move them
    Planner.plan = Planner.Build(recs, zoneMobs, {
        ladder = MK.Team:GetLadder(),
        ccSlots = MK.Team:GetCCSlots(),
        reserved = reserved,
    })
    Planner.plan.skipped = skipped
    Planner.plan.onCorpses = onCorpses
    Planner.plan.stale = stale
    -- Remember the levels each learned model entry is seen at (shown in the mob database window).
    if zoneMobs then
        for _, rec in ipairs(recs) do
            local entry = rec.model and zoneMobs.sigs[rec.sig]
            if entry then MK.MobDB.NoteLevel(entry, rec.level) end
        end
    end
    MK:Fire("PLAN_CHANGED", Planner.plan)
end

-- Name, else the player's note on the signature, else "lvl 15 elite caster"
function Planner.Describe(entryOrRec)
    local rec = entryOrRec.rec or entryOrRec
    return MK.MobDB:Label(rec)
end

-- "Humanoid", "Humanoid (data)" when it came from the offline instance data, "type ?"; plus CC immunities.
function Planner.TypeText(rec)
    local text = rec.ctype or "type ?"
    if rec.ctypeSource == "data" then text = text .. " (data)" end
    if rec.tierSource == "data" then text = text .. ", boss (data)" end
    if rec.immune and rec.immune ~= "" then text = text .. ", immune " .. rec.immune end
    return text
end

function Planner:Report()
    local plan, L = Planner.plan, MK.L
    if #plan.entries == 0 then
        MK:Print(L["PLAN_EMPTY"])
    else
        MK:Print(L["PLAN_HEADER"], #plan.entries)
    end
    local sorted = {}
    for _, e in ipairs(plan.entries) do table.insert(sorted, e) end
    table.sort(sorted, function(a, b) return a.icon > b.icon end)
    for _, e in ipairs(sorted) do
        local detail = string.format("%s (%s, prio %d, %s, %s)", Planner.Describe(e), e.reason, e.prio, e.source,
            Planner.TypeText(e.rec))
        print(string.format(L["PLAN_LINE"], Utils.IconText(e.icon), detail))
    end
    -- Every other plate and why it has no icon (players left out: noise).
    for _, rec in ipairs(plan.overflow) do
        print(string.format(L["PLAN_NO_ICON"], Planner.Describe(rec), L["SKIP_OVERFLOW"]))
    end
    for _, s in ipairs(plan.skipped or {}) do
        if s.reason ~= "SKIP_PLAYER" then
            print(string.format(L["PLAN_NO_ICON"], Planner.Describe(s.rec), L[s.reason]))
        end
    end
    -- Icons the plan leaves alone (a living mob wears them) and icons on corpses (free to reuse).
    local function IconList(set)
        local list = {}
        for icon = 8, 1, -1 do
            if set and set[icon] then table.insert(list, Utils.IconText(icon)) end
        end
        return table.concat(list, " ")
    end
    local worn, corpses = IconList(plan.reserved), IconList(plan.onCorpses)
    if worn ~= "" then print(string.format(L["PLAN_WORN"], worn)) end
    -- Why each kept icon is kept (what MK knows about who put it there).
    local follow = MK.Team:FollowIcons()
    for icon = 8, 1, -1 do
        if plan.reserved and plan.reserved[icon] then
            local placed, why = Planner.placed[icon], nil
            if follow[icon] then why = L["WORN_FOLLOW"]
            elseif placed == nil then why = L["WORN_NOT_OURS"]
            elseif placed == false then why = L["WORN_NO_PLATE"]
            else why = L["WORN_ALIVE"] end
            print(string.format("    %s %s", Utils.IconText(icon), why))
        end
    end
    if corpses ~= "" then print(string.format(L["PLAN_CORPSES"], corpses)) end
    local stale = IconList(plan.stale)
    if stale ~= "" then print(string.format(L["PLAN_STALE"], stale)) end
    if InCombatLockdown() then MK:Print(L["PLAN_FROZEN"]) end
end

function Planner:OnInitialize()
    MK:On("PLATES_CHANGED", function() Planner:Rebuild() end)
    if SetRaidTarget then hooksecurefunc("SetRaidTarget", OnSetRaidTarget) end
    if RemoveRaidTargets then hooksecurefunc("RemoveRaidTargets", function() wipe(Planner.placed) end) end
end
