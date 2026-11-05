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

-- What the API docs mark as possibly secret, each with a value that shows the guard's choice:
-- the mock's secrets compare freely, so only a different result can fail here (ruleset plan
-- 2026-11-05-audit-fixes; the code audit's C-03 and C-04)
describe("values the client may keep secret", function()
    local function group(ns)
        STATE.group, STATE.members = true, 2
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
        return ns
    end

    it("give no target level while the self check is secret", function()
        local ns = login()
        STATE.target = true
        STATE.units.target = { level = 33 }
        assert.are.equal(33, ns.TargetPlayerLevel())
        STATE.secrets[false] = true
        assert.is_nil(ns.TargetPlayerLevel())
    end)

    it("start no trade while the self check is secret", function()
        local ns = login()
        STATE.target = true
        STATE.units.target = {}
        STATE.secrets[false] = true
        _G.CHAT = {}
        RUNSCRIPT(ns.buttons.Water, "OnClick", "MiddleButton", false)
        assert.is_truthy(CHAT[#CHAT]:find(ns.L.TRADE_NO_TARGET, 1, true))
        assert.are.same({}, STATE.errors)
    end)

    it("leave the range check to decide while the self check is secret", function()
        local ns = login()
        STATE.target = true
        STATE.units.target = { is = "player", range = false }
        STATE.secrets[true] = true
        local spell, why = ns.BuffRunSpell("target")
        assert.is_nil(spell)
        assert.is_truthy(why:find("range", 1, true), why)
    end)

    it("count an aura whose ID cannot be read as our strength", function()
        -- the addon keeps the function it finds at load, so it is replaced before that
        local ns = group(login(function()
            C_UnitAuras.GetAuraDataBySpellName = function()
                return setmetatable({ expirationTime = STATE.now + 3600 }, { __index = function(_, k)
                    if k == "spellId" then error("secret") end
                end })
            end
        end))
        STATE.units.party1 = { class = "PRIEST" }
        local ok, err = pcall(ns.UpdateBuffState)
        assert.is_true(ok, err)
        local count = ns.buttons.Intellect.count:GetText()
        assert.is_true(count == nil or count == 0 or count == "", tostring(count))
    end)

    it("count a member of a secret class as a mana user", function()
        local ns = group(login())
        STATE.units.player = { auras = { ns.D.SPELL_ARCANE_INTELLECT } }
        STATE.units.party1 = { class = "WARRIOR" }
        STATE.secrets.WARRIOR = true
        ns.UpdateBuffState()
        assert.are.equal(1, ns.buttons.Intellect.count:GetText())
        STATE.units.target = { class = "WARRIOR" }
        STATE.target = true
        assert.is_truthy((ns.BuffRunSpell("target")))
    end)

    it("pass a target whose PvP flag is secret, and call nobody flagged for good", function()
        local ns = login()
        STATE.target = true
        STATE.units.target = {}
        STATE.secrets[false] = true -- the flag reads false, but cannot be trusted
        local spell, why = ns.BuffRunSpell("target")
        assert.is_nil(spell)
        assert.are.equal("flagged for PvP", why)
        STATE.secrets[false] = nil
        STATE.units.player = { pvp = true }
        STATE.units.target = { pvp = true }
        STATE.secrets[true] = true
        spell, why = ns.BuffRunSpell("target")
        assert.is_nil(spell)
        assert.are.equal("flagged for PvP", why)
    end)

    it("treat a secret cooldown as no cooldown", function()
        local ns = login()
        STATE.target = true
        STATE.units.target = {}
        local real = C_Spell.GetSpellCooldown
        C_Spell.GetSpellCooldown = function() return { startTime = 5, duration = 1.5 } end
        STATE.secrets[5] = true
        RUNSCRIPT(ns.buttons.Intellect, "PreClick", "MiddleButton", true)
        C_Spell.GetSpellCooldown = real
        local log = table.concat(ns.LogLines(), "\n")
        assert.is_truthy(log:find("buffrun ", 1, true), log)
        assert.is_nil(log:find("wait: cooldown", 1, true), log)
    end)
end)

describe("a damaged saved position", function()
    it("is dropped before it reaches SetPoint, and a valid one stays", function()
        _G.SimpleConjureBarDB = { point = "FOO", rel = "ALSONOT", x = 1, y = 2 }
        addon.load("enUS").InitDB()
        assert.is_nil(SimpleConjureBarDB.point)
        assert.is_nil(SimpleConjureBarDB.rel)
        _G.SimpleConjureBarDB = { point = "TOPLEFT", rel = "BOTTOMRIGHT", x = 1, y = 2 }
        addon.load("enUS").InitDB()
        assert.are.equal("TOPLEFT", SimpleConjureBarDB.point)
    end)
end)
