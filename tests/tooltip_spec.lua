-- The Intellect tooltip names what each click casts and on whom, the left click too; a left
-- click on the handle in combat says why nothing happens
-- (ruleset plan 2026-10-21-bar-alignment, items 2 and 3).

local addon = require("addon")

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns
end

-- The lines the Intellect button's tooltip adds, in order
local function tooltipLines(ns)
    local lines = {}
    GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    ns.ShowTooltip(ns.buttons.Intellect)
    return lines
end

local function has(lines, wanted)
    for _, l in ipairs(lines) do if l == wanted then return true end end
    return false
end

local function regroup(ns, group, raid, members)
    STATE.group, STATE.raid, STATE.members = group, raid, members
    FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
    ns.UpdateBuffState()
end

describe("the Intellect tooltip", function()
    it("names no target solo", function()
        local ns = login()
        regroup(ns, false, false, 0)
        local b, L = ns.buttons.Intellect, ns.L
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1")))))
    end)

    it("names the member a single buff goes to, and Brilliance's group, in a party", function()
        local ns = login()
        local b, L = ns.buttons.Intellect, ns.L
        regroup(ns, true, false, 3)
        -- Brilliance on the left in a group, while it is known and powder is in the bags
        assert.are.equal(ns.D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(ns.D.SPELL_ARCANE_BRILLIANCE)
            .. " > " .. L.TARGET_GROUP)), table.concat(lines, " | "))

        -- Without powder the left click is the single buff, on a member by name
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 0
        ns.UpdateBuffState()
        local unit = b:GetAttribute("unit1")
        lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1"))
            .. " > " .. UnitName(unit))), table.concat(lines, " | "))
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 5
    end)

    it("names Brilliance's subgroup by number in a raid", function()
        local ns = login()
        local b, L = ns.buttons.Intellect, ns.L
        regroup(ns, true, true, 12)
        local unit = b:GetAttribute("unit1")
        local index = tonumber(unit:match("^raid(%d+)$"))
        assert.is_not_nil(index, unit)
        local sub = select(3, GetRaidRosterInfo(index))
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(ns.D.SPELL_ARCANE_BRILLIANCE)
            .. " > " .. L.TARGET_SUBGROUP:format(sub))), table.concat(lines, " | "))
        assert.are.same({}, STATE.errors)
    end)
end)

describe("the handle", function()
    it("says why a left click in combat does nothing, and stays quiet out of it", function()
        local ns = login()
        SimpleConjureBarDB.locked = true
        _G.CHAT = {}
        RUNSCRIPT(ns.handle, "OnMouseDown", "LeftButton")
        assert.are.same({}, CHAT)

        STATE.combat = true
        RUNSCRIPT(ns.handle, "OnMouseDown", "LeftButton")
        assert.are.equal(1, #CHAT)
        assert.is_truthy(CHAT[1]:find(ns.L.NOT_IN_COMBAT, 1, true))
        STATE.combat = false
    end)
end)
