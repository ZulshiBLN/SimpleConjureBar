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
