-- Moving over from TankMarkForever: key bindings move from TMF_* to BWK_* buttons, macros that still /click TMF_
-- are listed; Marking waits while TankMarkForever is loaded. Plus the Options/Keys pages and /bwk mark commands.
local H = require("mark_helpers")

-- Models key bindings and macros (wowsim doesn't): bindings[action] = { keys }, macros[index] = { name, body }.
local function install(s, bindings, macros)
    H.install(s)
    s.bindings, s.saved = bindings, 0
    s.env.GetBindingKey = function(action)
        local keys = s.bindings[action]
        if keys then return unpack(keys) end
    end
    s.env.SetBinding = function(key, action)
        for _, keys in pairs(s.bindings) do
            for i = #keys, 1, -1 do if keys[i] == key then table.remove(keys, i) end end
        end
        s.bindings[action] = s.bindings[action] or {}
        table.insert(s.bindings[action], key)
        return true
    end
    s.env.SaveBindings = function() s.saved = s.saved + 1 end
    s.env.GetCurrentBindingSet = function() return 2 end
    s.env.GetNumMacros = function() return 1, 1 end
    s.env.GetMacroInfo = function(index)
        local m = macros[index]
        if m then return m.name, 136000, m.body end
    end
end

local OLD_PACK, NEW_PACK = "CLICK TMF_PackButton:LeftButton", "CLICK BWK_PackButton:LeftButton"
local OLD_SKULL, NEW_SKULL = "CLICK TMF_SkullButton:LeftButton", "CLICK BWK_SkullButton:LeftButton"

return function(_, t)
    -- Login with TankMarkForever gone: its keys move to Bulwark's buttons, once, and are saved.
    local sim = t.fresh(function(s)
        install(s, { [OLD_PACK] = { "F" }, [OLD_SKULL] = { "SHIFT-F" } }, {
            [1] = { name = "Pull", body = "/click TMF_Follow1\n/click TMF_Mark1\n/cast Charge" },
            [121] = { name = "Clean", body = "/cast Taunt" },
        })
    end)
    t.eq(sim.bindings[NEW_PACK][1], "F", "pack key moved")
    t.eq(sim.bindings[NEW_SKULL][1], "SHIFT-F", "skull key moved")
    t.eq(#sim.bindings[OLD_PACK], 0, "old binding gone")
    t.eq(sim.saved, 1, "bindings saved once")
    t.contains(sim.output, "work with Bulwark", "player told the keys moved")
    t.contains(sim.output, "TMF_ to BWK_.*Pull", "old macro listed by name")
    t.eq(sim.env.BulwarkDB.marking.keysMoved, true, "remembered")

    -- Keys page shows the new keys and the macro to fix; the button finds nothing left to move.
    local keys = H.page(sim, "keys")
    t.eq(keys.keys.PackButton:GetText(), "F", "pack key shown")
    t.ok(keys.keys.CycleButton:GetText():find("not bound"), "unbound key shown as such")
    t.ok(keys.macros:GetText():find("Pull", 1, true), "macro named on the page")
    t.eq(#sim.env.Bulwark.Marking.Keys.MoveOldBindings(), 0, "nothing left to move")

    -- Options page writes the planning settings.
    local options = H.page(sim, "options")
    options.boxes.overlay:Click()
    t.eq(sim.env.BulwarkDB.marking.overlay, false, "overlay checkbox")
    options.boxes.shiftSelect:Click()
    t.eq(sim.env.BulwarkDB.marking.shiftSelect, false, "shift-select checkbox")

    -- Commands.
    local printed = #sim.output
    sim:Slash("/bwk mark status")
    t.contains({ unpack(sim.output, printed + 1) }, "Keys: pack F", "status shows the keys")
    sim:Slash("/bwk mark announce")
    t.ok(sim.chat[#sim.chat] and sim.chat[#sim.chat].msg:find("^%[Bulwark%] Kill order:"), "announcement goes out branded")

    -- TankMarkForever still loaded: Marking waits; nothing moved, no HUD, no armed buttons.
    local s2 = t.fresh(function(s)
        install(s, { [OLD_PACK] = { "F" } }, {})
        H.pack(s)
        s.env.C_AddOns.IsAddOnLoaded = function(name) return name == "Bulwark" or name == "TankMarkForever" end
    end)
    s2:Advance(1)
    t.eq(s2.env.Bulwark:AreaStatus("marking"), "blocked", "Marking waits for TankMarkForever")
    t.eq(s2.bindings[OLD_PACK][1], "F", "TankMark's keys left alone while it's loaded")
    t.ok(not (s2.env.Bulwark_MarkHUD and s2.env.Bulwark_MarkHUD:IsShown()), "no Bulwark HUD")
    t.eq(s2.env.BWK_PackButton:GetAttribute("macrotext"), "", "pack key not armed")
    printed = #s2.output
    s2:Slash("/bwk mark plan")
    t.contains({ unpack(s2.output, printed + 1) }, "off or waiting", "commands say why")
end
