-- Every change to the protected bar that comes in combat waits for its end: the client refuses
-- it (ADDON_ACTION_BLOCKED), which the mock records in STATE.errors. One spec per guard, each
-- shown failing with its guard removed (code review 1.1.0, F-03: mutants M20-M22, M31, M32).

local addon = require("addon")

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- As the client sends it: the event first, then the lockdown
local function enterCombat() FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true end
local function leaveCombat() STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS() end

local function auras(ns) FIRE("UNIT_AURA", "player"); RUNTIMERS(); ns.UpdateBuffState() end

describe("a change in combat", function()
    it("leaves the buff key as combat started, and sets it after", function()
        local ns = login()
        local key = ns.buffKey
        _G.AURAS["player" .. ns.SpellName(ns.D.ARMOR_BUFF_IDS[1])] = true
        _G.AURAS["player" .. ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT)] = true
        auras(ns)
        enterCombat()
        assert.are.equal("Armor", key:GetAttribute("scbsource"))
        ns.UpdateBuffKey() -- a glow change in combat
        assert.are.equal("Armor", key:GetAttribute("scbsource"))
        assert.are.same({}, STATE.errors)
        leaveCombat()
        assert.is_nil(key:GetAttribute("scbsource"))
        assert.are.same({}, STATE.errors)
    end)

    it("scales the bar after combat", function()
        local ns, db = login()
        enterCombat()
        db.scale = 1.5
        ns.ApplyScale()
        assert.are_not.equal(1.5, ns.bar:GetScale())
        leaveCombat()
        assert.are.equal(1.5, ns.bar:GetScale())
        assert.are.same({}, STATE.errors)
    end)

    it("switches Hide in combat after combat", function()
        local ns, db = login()
        assert.is_nil(ns.bar.stateDriver)
        enterCombat()
        db.hideCombat = true
        ns.ApplyCombatHide()
        assert.is_nil(ns.bar.stateDriver)
        leaveCombat()
        assert.are.same({ "visibility", "[combat] hide; show" }, ns.bar.stateDriver)
        assert.are.same({}, STATE.errors)
    end)

    it("fits the conjure rank to a new target after combat", function()
        local ns = login()
        local water = ns.buttons.Water
        local before = water:GetAttribute("spell2")
        -- the mock's items share one level; here the best one needs a higher level than the rest
        ns.ItemMinLevel = function(id) return id == water.items[1] and 55 or 1 end
        enterCombat()
        STATE.units.target = { level = 5 }
        FIRE("PLAYER_TARGET_CHANGED")
        assert.are.equal(before, water:GetAttribute("spell2"))
        leaveCombat()
        assert.are_not.equal(before, water:GetAttribute("spell2"))
        assert.are.same({}, STATE.errors)
    end)

    -- code review 1.1.0, F-06: demo mode in combat would print demo messages over real actions
    it("refuses demo mode in combat", function()
        local ns, db = login()
        enterCombat()
        _G.CHAT = {}
        SlashCmdList.SIMPLECONJUREBAR("demo")
        assert.is_false(db.demo)
        assert.is_truthy(CHAT[#CHAT]:find(ns.L.NOT_IN_COMBAT, 1, true))
        leaveCombat()
        SlashCmdList.SIMPLECONJUREBAR("demo")
        assert.is_true(db.demo)
        assert.are.same({}, STATE.errors)
    end)

    -- code review 1.1.0, F-01: a rebuild queued before the bar was set up saved the start
    -- position over the player's
    it("keeps the saved bar position after a login in combat", function()
        _G.SimpleConjureBarDB = { point = "LEFT", rel = "BOTTOMLEFT", x = 500, y = 600 }
        local ns = addon.load("enUS")
        STATE.combat = true
        FIRE("PLAYER_LOGIN"); RUNTIMERS()
        FIRE("SPELLS_CHANGED"); RUNTIMERS()
        leaveCombat()
        local db = SimpleConjureBarDB
        assert.are.same({ "LEFT", "BOTTOMLEFT", 500, 600 }, { db.point, db.rel, db.x, db.y })
        local point, _, rel, x, y = ns.bar:GetPoint(1)
        assert.are.same({ "LEFT", "BOTTOMLEFT", 500, 600 }, { point, rel, x, y })
        assert.are.same({}, STATE.errors)
    end)

    it("leaves the flyouts' close time to after combat", function()
        local ns, db = login()
        local before = ns.header:GetAttribute("autohide")
        enterCombat()
        db.flyoutAutoClose = before + 1
        ns.ApplyAutoClose()
        assert.are.equal(before, ns.header:GetAttribute("autohide"))
        assert.are.same({}, STATE.errors)
        leaveCombat()
    end)
end)

-- In combat the bar offers only what works there (ruleset plan 2026-10-25-combat-locks, item 1)
describe("the combat locks", function()
    it("drop water, food and the gem's conjure, grey them, hide Intellect's count, and give all back", function()
        local ns = login()
        local b = ns.buttons
        STATE.units.player = {} -- Intellect missing: a count and a glow before combat
        ns.UpdateBuffState()
        assert.are.equal(1, b.Intellect.count:GetText())
        assert.is_true(b.Intellect.antsShown)

        enterCombat()
        STATE.casts, STATE.uses = {}, {}
        for _, key in ipairs({ "Water", "Food" }) do
            for _, button in ipairs({ "LeftButton", "RightButton" }) do RUNCLICK(b[key], button, false) end
        end
        RUNCLICK(b.ManaGem, "RightButton", false)
        assert.are.same({}, STATE.casts)
        assert.are.same({}, STATE.uses)
        RUNCLICK(b.ManaGem, "LeftButton", false) -- a gem is still used
        assert.are.equal(b.ManaGem.leftItem, STATE.uses[1])

        for _, key in ipairs({ "Intellect", "Water", "Food", "Teleport", "Portal" }) do
            assert.is_true(b[key].icon.desaturated, key)
        end
        assert.are.equal("", b.Intellect.count:GetText())
        assert.is_false(b.Intellect.antsShown)
        for _, key in ipairs({ "Water", "Food" }) do
            assert.is_true(b[key].count.textColor[1] < 1, key)
        end
        assert.are.same({}, STATE.errors)

        leaveCombat()
        for _, key in ipairs({ "Intellect", "Water", "Food" }) do
            assert.is_false(b[key].icon.desaturated, key)
            assert.are.equal(1, b[key].icon:GetAlpha(), key)
        end
        assert.are.equal(1, b.Intellect.count:GetText())
        assert.is_true(b.Intellect.antsShown)
        assert.are.equal(1, b.Water.count.textColor[1])
        STATE.casts = {}
        RUNCLICK(b.Water, "RightButton", false)
        assert.are.same({ { spell = b.Water:GetAttribute("spell2") } }, STATE.casts)
        assert.are.same({}, STATE.errors)
    end)
end)

-- Auras are unreadable in combat: the armor's glow follows a cast there (ruleset plan
-- 2026-10-25-combat-locks, item 8)
describe("the armor glow in combat", function()
    local function cast(id) FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) end

    it("goes off with a cast of any mage armor, of any rank, and the aura decides after", function()
        local ns = login()
        local armor, D = ns.buttons.Armor, ns.D
        assert.is_true(armor.antsShown) -- no armor at login
        enterCombat()
        cast(D.SPELL_ARCANE_INTELLECT)
        FIRE("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", D.ARMOR_FAMILIES[1][1])
        assert.is_true(armor.antsShown)
        cast(D.ARMOR_FAMILIES[2][1]) -- not rank 1
        assert.is_false(armor.antsShown)
        leaveCombat()
        assert.is_true(armor.antsShown) -- no aura: needed again
        assert.are.same({}, STATE.errors)
    end)

    it("goes off with a press when the client keeps the spell ID secret", function()
        local ns = login()
        local armor, key = ns.buttons.Armor, ns.buffKey
        local id = armor:GetAttribute("spell1")
        STATE.secrets[id] = true
        enterCombat()
        cast(id) -- no press: someone else's cast cannot be told apart
        assert.is_true(armor.antsShown)
        RUNCLICK(armor, "LeftButton", true); RUNCLICK(armor, "LeftButton", false)
        cast(id)
        assert.is_false(armor.antsShown)
        leaveCombat()
        assert.is_true(armor.antsShown)

        enterCombat() -- the key holding the armor counts as a press too
        assert.are.equal("Armor", key:GetAttribute("scbsource"))
        RUNCLICK(key, "LeftButton", false)
        cast(id)
        assert.is_false(armor.antsShown)
        leaveCombat()
        assert.are.same({}, STATE.errors)
    end)
end)
