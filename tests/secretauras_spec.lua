-- In instances and PvP the client keeps auras secret out of combat too and refuses a read
-- (SmartBlessingBar's BugSack note, 2026-10-20). The bar then keeps what it showed instead of
-- reading every buff as missing (ruleset plan 2026-10-25-secret-auras).

local addon = require("addon")

local function login(adjust)
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS", adjust)
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

local function update(ns) FIRE("UNIT_AURA", "player"); RUNTIMERS(); ns.UpdateBuffState() end
local function cast(id) FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) end

describe("secret auras out of combat", function()
    it("keep the Intellect count, glow and target and the armor glow, while the settings follow", function()
        local ns, db = login()
        local D, intel, armor = ns.D, ns.buttons.Intellect, ns.buttons.Armor
        STATE.units.player = { auras = { D.ARMOR_BUFF_IDS[1] } } -- armor on, Intellect missing
        STATE.units.party1 = { class = "PRIEST" }
        STATE.group, STATE.members = true, 2
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS(); update(ns)
        local count, unit = intel.count:GetText(), intel:GetAttribute("unit1")
        assert.are.equal(2, count)
        assert.is_true(intel.antsShown)
        assert.is_false(armor.antsShown)

        STATE.secret = true -- an instance: everyone gets the buff, the armor runs out
        STATE.units.player = { auras = { D.SPELL_ARCANE_INTELLECT } }
        STATE.units.party1 = { class = "PRIEST", auras = { D.SPELL_ARCANE_INTELLECT } }
        update(ns); TICK()
        assert.are.equal(count, intel.count:GetText())
        assert.is_true(intel.antsShown)
        assert.are.equal(unit, intel:GetAttribute("unit1"))
        assert.is_false(armor.antsShown)
        db.buffRun = false; ns.UpdateBuffState() -- Buff & Run's switch still takes effect
        assert.is_nil(intel:GetAttribute("type3"))
        assert.are.same({}, STATE.errors)

        STATE.secret = false -- leaving it: the real state
        update(ns)
        assert.are.equal("", intel.count:GetText())
        assert.is_false(intel.antsShown)
        assert.is_true(armor.antsShown)
    end)

    it("do not freeze demo mode", function()
        local ns, db = login()
        local intel = ns.buttons.Intellect
        STATE.units.player = { auras = { ns.D.SPELL_ARCANE_INTELLECT } }
        update(ns)
        assert.are.equal("", intel.count:GetText())
        STATE.secret = true
        db.demo = true; ns.Rebuild(); RUNTIMERS()
        assert.are.equal(db.brillianceThreshold, intel.count:GetText()) -- demo's group at the threshold
        assert.are.same({}, STATE.errors)
    end)

    it("let an armor cast turn its glow off, until the aura can be read again", function()
        local ns = login()
        local D, armor = ns.D, ns.buttons.Armor
        assert.is_true(armor.antsShown) -- no armor
        STATE.secret = true
        cast(D.ARMOR_FAMILIES[1][1])
        assert.is_false(armor.antsShown)
        update(ns)
        assert.is_false(armor.antsShown) -- stays off while the aura cannot be read
        STATE.secret = false
        update(ns)
        assert.is_true(armor.antsShown) -- no armor aura after all: the aura decides
        assert.are.same({}, STATE.errors)
    end)

    it("count a cast with a secret ID only after a press on the armor", function()
        local ns = login()
        local armor = ns.buttons.Armor
        local id = armor:GetAttribute("spell1")
        STATE.secret = true
        STATE.secrets[id] = true
        cast(id) -- someone else's cast cannot be told apart
        assert.is_true(armor.antsShown)
        RUNCLICK(armor, "LeftButton", true); RUNCLICK(armor, "LeftButton", false)
        cast(id)
        assert.is_false(armor.antsShown)
        STATE.units.player = {} -- the press is used up: a second secret cast changes nothing
        ns.SetAnts(armor, true)
        cast(id)
        assert.is_true(armor.antsShown)
        assert.are.same({}, STATE.errors)
    end)
end)

describe("a login with auras secret", function()
    it("shows Intellect's icon without count, glow, click or line", function()
        local ns = login(function() STATE.secret = true end)
        local intel = ns.buttons.Intellect
        assert.are.equal(ns.D.INTELLECT_RANKS[1].id, intel.leftSpell)
        assert.is_not_nil(intel.icon.texture)
        assert.is_true(intel.count:GetText() == nil or intel.count:GetText() == "")
        assert.is_falsy(intel.antsShown)
        assert.is_nil(intel:GetAttribute("type1"))
        assert.is_nil(intel.hintLeft)
        assert.are.same({}, STATE.errors)
    end)

    it("counts a refused read as unreadable where the client has no C_Secrets", function()
        local ns = login(function() _G.C_Secrets = nil end)
        assert.is_true(ns.AurasReadable())
        STATE.secret = true
        assert.is_false(ns.AurasReadable())
    end)
end)

-- Trade compares and prints the target's name, level and class: each may be secret there
-- (ruleset plan 2026-10-25-secret-auras, item 6)
describe("a trade with a target whose values are secret", function()
    it("names him 'your target', takes your level and counts him a mana user, without an error", function()
        local ns = login()
        local L, D = ns.L, ns.D
        for _, list in ipairs({ D.WATER_ITEMS, D.FOOD_ITEMS }) do
            for _, id in ipairs(list) do ITEMS[id] = 0 end
        end
        STATE.target = true
        STATE.units.target = { name = "Secretguy", level = 37, class = "WARRIOR" }
        STATE.secrets.Secretguy, STATE.secrets[37], STATE.secrets.WARRIOR = true, true, true
        _G.CHAT = {}
        RUNSCRIPT(ns.buttons.Water, "OnClick", "MiddleButton", false)
        local line = table.concat(CHAT, " ")
        assert.is_nil(line:find("Secretguy", 1, true), line)
        assert.is_truthy(line:find(L.TRADE_TARGET, 1, true), line)
        assert.is_truthy(line:find(L.WATER, 1, true), line) -- a secret class counts as a mana user
        assert.is_truthy(line:find("(level " .. UnitLevel("player") .. ")", 1, true), line)
        assert.are.same({}, STATE.errors)
    end)
end)
