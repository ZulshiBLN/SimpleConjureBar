-- The mana gem, water and food show what a click does: no action and no line where a click has
-- nothing to do; the gem glows while the highest known gem is missing, never in combat
-- (ruleset plan 2026-10-25-combat-locks, items 4 to 6).

local addon = require("addon")

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns
end

local function bags() FIRE("BAG_UPDATE_DELAYED"); RUNTIMERS() end

-- The gems in the bags, highest first, as counts; the rest none
local function own(ns, ...)
    local counts = { ... }
    for i, g in ipairs(ns.D.MANA_GEMS) do ITEMS[g.item] = counts[i] or 0 end
    bags()
end

local function enterCombat() FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true end
local function leaveCombat() STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS() end

describe("the mana gem out of combat", function()
    it("glows while the highest known gem is missing, and conjures the highest one not owned", function()
        local ns = login()
        local gem, G = ns.buttons.ManaGem, ns.D.MANA_GEMS
        own(ns, 1)
        assert.is_false(gem.antsShown)
        assert.are.equal(G[2].spell, gem:GetAttribute("spell2"))

        own(ns, 0, 1) -- only a lower gem
        assert.is_true(gem.antsShown)
        assert.are.equal(G[2].item, gem.leftItem)
        assert.are.equal(G[1].spell, gem:GetAttribute("spell2"))
        assert.are.same({}, STATE.errors)
    end)

    it("has no right action and no right line with every known gem owned", function()
        local ns = login()
        local gem = ns.buttons.ManaGem
        own(ns, 1, 1, 1, 1)
        assert.is_nil(gem:GetAttribute("type2"))
        assert.is_nil(gem.hint)
        assert.is_false(gem.antsShown)
        assert.are_not.equal("ManaGem", ns.buffKey:GetAttribute("scbsource"))
        assert.are.same({}, STATE.errors)
    end)

    it("has no left action and no left line without a gem", function()
        local ns = login()
        local gem, L = ns.buttons.ManaGem, ns.L
        own(ns)
        assert.is_nil(gem:GetAttribute("type1"))
        assert.is_nil(gem.hintLeft)
        assert.are.equal(L.HINT_RIGHT:format(ns.SpellName(ns.D.MANA_GEMS[1].spell)), gem.hint)
        assert.is_true(gem.antsShown)
        assert.are.same({}, STATE.errors)
    end)
end)

describe("the mana gem in combat", function()
    it("never glows, and shows the next gem once one is used", function()
        local ns = login()
        local gem, G, L = ns.buttons.ManaGem, ns.D.MANA_GEMS, ns.L
        own(ns, 1, 1)
        enterCombat()
        ITEMS[G[1].item] = 0; bags() -- the highest used: the glow would come back
        assert.is_false(gem.antsShown)
        assert.are.equal(G[2].item, gem.leftItem)
        assert.are.equal(C_Item.GetItemIconByID(G[2].item), gem.icon.texture)
        assert.are.equal(L.HINT_USE_ITEM:format(C_Item.GetItemNameByID(G[2].item)), gem.hintLeft)
        assert.is_false(gem.icon.desaturated)

        ITEMS[G[2].item] = 0; bags() -- the last one used: greyed
        assert.is_true(gem.icon.desaturated)
        assert.is_false(gem.antsShown)
        assert.are.same({}, STATE.errors)
        leaveCombat()
        assert.is_false(gem.icon.desaturated)
        assert.is_true(gem.antsShown)
        assert.are.same({}, STATE.errors)
    end)

    it("is greyed from combat start without a gem", function()
        local ns = login()
        local gem = ns.buttons.ManaGem
        own(ns)
        enterCombat()
        assert.is_true(gem.icon.desaturated)
        assert.is_false(gem.antsShown)
        leaveCombat()
        assert.is_false(gem.icon.desaturated)
        assert.are.same({}, STATE.errors)
    end)
end)

describe("water and food without stock", function()
    it("have no left action and no left line, and conjure on the right", function()
        local ns = login()
        local b, D = ns.buttons, ns.D
        for _, list in ipairs({ D.WATER_ITEMS, D.FOOD_ITEMS }) do
            for _, id in ipairs(list) do ITEMS[id] = 0 end
        end
        bags()
        for _, key in ipairs({ "Water", "Food" }) do
            assert.is_nil(b[key]:GetAttribute("type1"), key)
            assert.is_nil(b[key].hintLeft, key)
            assert.are.equal("spell", b[key]:GetAttribute("type2"), key)
        end
        assert.are.same({}, STATE.errors)
    end)
end)
