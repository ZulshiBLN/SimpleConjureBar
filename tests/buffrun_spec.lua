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

    -- ruleset plan 2026-10-23-intellect-range: a lower rank with time left takes ours
    it("casts our rank on a lower rank with time left", function()
        local ns = login()
        local D = ns.D
        local lowest = D.INTELLECT_RANKS[#D.INTELLECT_RANKS].id
        local weak = { id = lowest, as = D.SPELL_ARCANE_INTELLECT, expires = GetTime() + 1800 }
        assert.are.equal(rankFor(D, 60), choice(ns, { class = "PRIEST", level = 60, auras = { weak } }))
        local ours = { id = rankFor(D, 60), as = D.SPELL_ARCANE_INTELLECT, expires = GetTime() + 1800 }
        assert.is_nil(choice(ns, { class = "PRIEST", level = 60, auras = { ours } }))
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

-- A check box of the settings window by its label text
local function checkBox(label)
    local function find(frame)
        for _, c in ipairs(frame.children) do
            if c.kind == "CheckButton" then
                for _, r in ipairs(c.regions) do if r.text == label then return c end end
            end
            local hit = find(c)
            if hit then return hit end
        end
    end
    return find(SimpleConjureBarSettings)
end

local function toggle(cb)
    cb:SetChecked(not cb:GetChecked())
    RUNSCRIPT(cb, "OnClick")
end

describe("Buff & Run and the PvP flag", function()
    -- The mage: not flagged, flagged with the flag running out (the "accidental" one), or
    -- flagged for good - /pvp, a battleground, a PvP zone (ruleset plan 2026-10-22-pvp-self-flag)
    local SELF = {
        unflagged = { pvp = false, timer = false },
        ["flagged, timer running"] = { pvp = true, timer = true },
        ["flagged for good"] = { pvp = true, timer = false },
    }
    local function as(state)
        STATE.units.player = { pvp = state.pvp }
        STATE.pvpTimer = state.timer
    end

    it("passes flagged players unless the mage is flagged for good or the box allows it", function()
        local ns, db = login()
        for name, state in pairs(SELF) do
            as(state)
            db.pvpBuff = false
            local flagged = choice(ns, { class = "PRIEST", pvp = true })
            if name == "flagged for good" then
                assert.is_not_nil(flagged, name)
            else
                assert.is_nil(flagged, name)
            end
            assert.is_not_nil(choice(ns, { class = "PRIEST" }), name .. ", unflagged target")
            db.pvpBuff = true
            assert.is_not_nil(choice(ns, { class = "PRIEST", pvp = true }), name .. ", box on")
        end
    end)

    -- Buffing yourself flags nothing (code review 1.1.0, F-05)
    it("never passes the mage, targeted, for the mage's own flag", function()
        local ns = login()
        as(SELF["flagged, timer running"])
        assert.is_not_nil(choice(ns, { is = "player", class = "MAGE", pvp = true }))
        assert.is_nil(choice(ns, { class = "MAGE", pvp = true })) -- another flagged mage still is
    end)

    it("logs why a flagged player was passed while the mage's flag runs out", function()
        local ns = login()
        as(SELF["flagged, timer running"])
        STATE.units.target = { class = "PRIEST", pvp = true }
        STATE.friends = { { class = "MAGE" } }
        middle(ns)
        local found
        for _, l in ipairs(ns.LogLines()) do
            if l:find("buffrun none: flagged for PvP", 1, true) then found = true end
        end
        assert.is_true(found)
    end)
end)

describe("the Buff & Run cooldown check", function()
    it("takes a spell the client answers no cooldown for, as an unlearned rank in demo mode", function()
        local ns = login()
        local get = C_Spell.GetSpellCooldown
        C_Spell.GetSpellCooldown = function() return nil end
        STATE.units.target = { class = "PRIEST" }
        STATE.friends = { { class = "MAGE" } }
        middle(ns)
        C_Spell.GetSpellCooldown = get
        assert.are.same({}, STATE.errors)
        assert.are.equal(1, #STATE.casts)
    end)
end)

describe("the Buff & Run switches", function()
    it("turn the middle click off and on through the check box, the PvP box dimmed while off", function()
        local ns, db = login()
        local L = ns.L
        ns.ToggleSettings()
        local box, pvp = checkBox(L.OPT_BUFF_RUN), checkBox(L.OPT_PVP_BUFF)
        assert.is_not_nil(box); assert.is_not_nil(pvp)
        assert.is_true(box:GetChecked())
        assert.is_true(select(2, pvp:GetPoint()) > select(2, box:GetPoint())) -- indented
        assert.are.equal(1, pvp:GetAlpha())

        toggle(box)
        assert.is_false(db.buffRun)
        assert.is_true(pvp:GetAlpha() < 1)
        STATE.units.target = { class = "PRIEST" }
        STATE.friends = { { class = "MAGE" } }
        middle(ns)
        assert.are.same({ {}, 0 }, { STATE.casts, STATE.targetedNext })

        toggle(box)
        assert.are.equal(1, pvp:GetAlpha())
        middle(ns)
        assert.are.equal(1, #STATE.casts)
        assert.are.equal(1, STATE.targetedNext)

        toggle(pvp)
        assert.is_true(db.pvpBuff)
    end)

    it("are in settings version 4, a damaged value replaced", function()
        local _, db = login({ dbVersion = 3 })
        assert.are.same({ true, false }, { db.buffRun, db.pvpBuff })
        _, db = login({ dbVersion = 4, buffRun = "x", pvpBuff = 1 })
        assert.are.same({ true, false }, { db.buffRun, db.pvpBuff })
        _, db = login({ dbVersion = 4, buffRun = false, pvpBuff = true })
        assert.are.same({ false, true }, { db.buffRun, db.pvpBuff })
    end)

    it("show in the Intellect tooltip while on", function()
        local ns, db = login()
        local lines
        GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
        local function has(wanted)
            lines = {}
            ns.ShowTooltip(ns.buttons.Intellect)
            for _, l in ipairs(lines) do if l == wanted then return true end end
            return false
        end
        assert.is_true(has(ns.L.HINT_BUFF_RUN))
        db.buffRun = false; ns.UpdateBuffState()
        assert.is_false(has(ns.L.HINT_BUFF_RUN))
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
            -- armed again, so only the combat lock can stop the clicks below (code review
            -- 1.1.0, F-02: the cooldown click had left the middle click empty)
            ns.UpdateBuffState()
            assert.are.equal("macro", ns.buttons.Intellect:GetAttribute("type3"))

            FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
            middle(ns)
            assert.are.same({ {}, 0 }, { STATE.casts, STATE.targetedNext })
            for _, button in ipairs({ "LeftButton", "RightButton" }) do
                RUNCLICK(ns.buttons.Intellect, button, keyDown)
                RUNCLICK(ns.buttons.Intellect, button, not keyDown)
            end
            assert.are.same({}, STATE.casts)
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
