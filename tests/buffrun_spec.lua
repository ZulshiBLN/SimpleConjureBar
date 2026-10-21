-- Buff & Run: the Intellect button's middle click buffs the target with Arcane Intellect, then
-- targets the next friendly player (ruleset plan 2026-10-21-buff-and-run).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- The rank a target of this level accepts, from Data.lua: the first, highest, whose level is
-- at most 10 above his
local function rankFor(D, level)
    for _, r in ipairs(D.INTELLECT_RANKS) do
        if r.level - 10 <= level then return r.id end
    end
end

local function choice(ns, target)
    STATE.units.target = target
    return ns.BuffRunSpell("target")
end

-- One middle click as the client delivers it: press and release
local function middle(ns)
    RUNCLICK(ns.buttons.Intellect, "MiddleButton", true)
    RUNCLICK(ns.buttons.Intellect, "MiddleButton", false)
end

describe("the Buff & Run choice", function()
    it("gives a friendly mana user the Arcane Intellect rank his level accepts, never Brilliance", function()
        local ns = login()
        local D = ns.D
        -- Brilliance is known and powder is in the bags (the mock's defaults)
        assert.is_true(ITEMS[D.ITEM_ARCANE_POWDER] > 0)
        for _, case in ipairs({ { "PRIEST", 60 }, { "HUNTER", 30 }, { "PALADIN", 20 }, { "DRUID", 5 } }) do
            local spell = choice(ns, { class = case[1], level = case[2] })
            assert.are.equal(rankFor(D, case[2]), spell, case[1])
            assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, spell)
        end
        -- A level the client hides ("??") is no reason for rank 1
        assert.are.equal(D.INTELLECT_RANKS[1].id, choice(ns, { class = "MAGE", level = -1 }))
    end)

    it("passes whoever does not need it or cannot get it", function()
        local ns = login()
        local D = ns.D
        local cases = {
            warrior = { class = "WARRIOR" }, rogue = { class = "ROGUE" },
            ["with Intellect"] = { class = "PRIEST", auras = { D.SPELL_ARCANE_INTELLECT } },
            ["with Brilliance"] = { class = "PRIEST", auras = { D.SPELL_ARCANE_BRILLIANCE } },
            ["with a stronger scroll"] = { class = "PRIEST", level = 20, auras = { 12176 } },
            dead = { class = "PRIEST", dead = true }, offline = { class = "PRIEST", connected = false },
            hostile = { class = "PRIEST", assist = false }, ["not a player"] = { class = "PRIEST", player = false },
            ["out of range"] = { class = "PRIEST", range = false },
            ["flagged for PvP"] = { class = "PRIEST", pvp = true },
        }
        for name, target in pairs(cases) do
            assert.is_nil(choice(ns, target), name)
        end
        -- A weaker scroll does not count
        assert.are.equal(rankFor(D, 20), choice(ns, { class = "PRIEST", level = 20, auras = { 8098 } }))
    end)

    it("buffs a flagged player once allowed, and nobody while auras are secret", function()
        local ns, db = login()
        db.pvpBuff = true
        assert.is_not_nil(choice(ns, { class = "PRIEST", pvp = true }))
        STATE.secret = true
        assert.is_nil(choice(ns, { class = "PRIEST" }))
        STATE.secret = false
    end)
end)

describe("the Buff & Run click", function()
    for _, keyDown in ipairs({ false, true }) do
        local mode = keyDown and " (actions on key down)" or " (actions on key up)"

        it("casts on the target and targets the next player" .. mode, function()
            local ns = login()
            STATE.keyDown = keyDown
            local spell = rankFor(ns.D, 60)
            STATE.units.target = { class = "PRIEST" }
            STATE.friends = { { class = "WARRIOR" } }
            middle(ns)
            assert.are.same({ { spell = spell, unit = "target" } }, STATE.casts)
            assert.are.equal(1, STATE.targetedNext)
            assert.are.equal("WARRIOR", STATE.units.target.class)

            -- Nothing for him: only on to the next
            STATE.friends = { { class = "MAGE" } }
            middle(ns)
            assert.are.equal(1, #STATE.casts)
            assert.are.equal(2, STATE.targetedNext)
            assert.are.same({}, STATE.errors)
        end)

        it("does nothing during the spell's cooldown, nor in combat" .. mode, function()
            local ns = login()
            STATE.keyDown = keyDown
            local spell = rankFor(ns.D, 60)
            STATE.units.target = { class = "PRIEST" }
            STATE.friends = { { class = "MAGE" } }
            STATE.cooldowns[spell] = 100
            middle(ns)
            assert.are.same({ {}, 0 }, { STATE.casts, STATE.targetedNext })
            STATE.cooldowns[spell] = nil

            STATE.combat = true; FIRE("PLAYER_REGEN_DISABLED")
            middle(ns)
            assert.are.same({ {}, 0 }, { STATE.casts, STATE.targetedNext })
            STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
            middle(ns)
            assert.are.same({ { spell = spell, unit = "target" } }, STATE.casts)
        end)

        it("works with the Intellect button hidden since login" .. mode, function()
            local ns = login({ showIntellect = false })
            STATE.keyDown = keyDown
            assert.is_false(ns.buttons.Intellect:IsShown())
            STATE.units.target = { class = "PRIEST" }
            STATE.friends = { { class = "MAGE" } }
            middle(ns)
            assert.are.same({ { spell = rankFor(ns.D, 60), unit = "target" } }, STATE.casts)
            assert.are.equal(1, STATE.targetedNext)
        end)

        it("in demo mode casts nothing, says once what it would, and targets on" .. mode, function()
            local ns, db = login()
            STATE.keyDown = keyDown
            db.demo = true; ns.Rebuild()
            STATE.units.target = { class = "PRIEST" }
            STATE.friends = { { class = "MAGE" } }
            _G.CHAT = {}
            middle(ns)
            assert.are.same({}, STATE.casts)
            assert.are.equal(1, #CHAT)
            assert.is_truthy(CHAT[1]:find(ns.SpellName(rankFor(ns.D, 60)), 1, true))
            assert.are.equal(1, STATE.targetedNext)
        end)
    end
end)
