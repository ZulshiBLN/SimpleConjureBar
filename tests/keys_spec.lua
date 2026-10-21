-- Two key bindings: "Cast next buff" casts what clears the first glowing button of the bar, and
-- a key opens the settings (ruleset plan 2026-10-21-bar-alignment, item 5).

local addon = require("addon")

local BUFF_KEY, SETTINGS_KEY = "SimpleConjureBarBuffAll", "SimpleConjureBarSettingsKey"
local BINDINGS = {
    ["CLICK " .. BUFF_KEY .. ":LeftButton"] = "KEY_BUFF_ALL",
    ["CLICK " .. SETTINGS_KEY .. ":LeftButton"] = "OPEN_SETTINGS",
    -- Buff & Run: the Intellect button's middle click itself (ruleset plan 2026-10-21-buff-and-run)
    ["CLICK SimpleConjureBar_Intellect:MiddleButton"] = "BUFF_RUN",
}

local function login(locale, adjust)
    _G.SimpleConjureBarDB = nil
    local ns = addon.load(locale or "enUS", adjust)
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- The action the buff key holds for a left click
local function action(key)
    return { key:GetAttribute("type1"), key:GetAttribute("spell1"), key:GetAttribute("unit1") }
end

-- What clears a button: Armor's and Intellect's left click, the gem's right click (conjure)
local function clears(b, rightClick)
    local n = rightClick and "2" or "1"
    return { b:GetAttribute("type" .. n), b:GetAttribute("spell" .. n), not rightClick and b:GetAttribute("unit1") or nil }
end

local function bags() FIRE("BAG_UPDATE_DELAYED"); RUNTIMERS() end
local function auras(ns) FIRE("UNIT_AURA", "player"); RUNTIMERS(); ns.UpdateBuffState() end

describe("Bindings.xml", function()
    it("lists exactly its keys, in a section of their own, on frames that exist", function()
        local f = assert(io.open("SimpleConjureBar/Bindings.xml", "rb"))
        local xml = f:read("*a"); f:close()
        local found = {}
        for name, category in xml:gmatch('<Binding%s+name="([^"]+)"%s+category="([^"]+)"') do
            found[name] = category
        end
        local expected = {}
        for name in pairs(BINDINGS) do expected[name] = "BINDING_HEADER_SIMPLECONJUREBAR" end
        assert.are.same(expected, found)
        login()
        assert.is_not_nil(_G[BUFF_KEY]); assert.is_not_nil(_G[SETTINGS_KEY])
    end)
end)

describe("the key names", function()
    it("follow the addon language for a mage", function()
        local ns = login("enUS")
        assert.are.equal("SimpleConjureBar", BINDING_HEADER_SIMPLECONJUREBAR)
        for name, key in pairs(BINDINGS) do
            assert.is_string(ns.locales.enUS[key], key)
            assert.are.equal(ns.locales.enUS[key], _G["BINDING_NAME_" .. name])
        end
        ns.ApplyLanguage("deDE")
        for name, key in pairs(BINDINGS) do
            assert.is_string(ns.locales.deDE[key], key)
            assert.are.equal(ns.locales.deDE[key], _G["BINDING_NAME_" .. name])
        end
    end)

    it("are in the client's language for another class", function()
        local ns = login("frFR", function() _G.UnitClass = function() return "Paladin", "PALADIN" end end)
        assert.is_false(ns.enabled)
        for name, key in pairs(BINDINGS) do
            assert.is_string(ns.locales.frFR[key], key)
            assert.are.equal(ns.locales.frFR[key], _G["BINDING_NAME_" .. name])
        end
    end)
end)

describe("Cast next buff", function()
    it("holds what clears the first glowing, shown button, and none when none glows", function()
        local ns, db = login()
        local b, key = ns.buttons, _G[BUFF_KEY]
        -- Solo: no armor, no Intellect, a gem in the bags - Armor comes first in the order
        assert.are.same(clears(b.Armor), action(key))

        _G.AURAS["player" .. ns.SpellName(ns.D.ARMOR_BUFF_IDS[1])] = true
        auras(ns)
        assert.is_false(b.Armor.antsShown)
        assert.are.same(clears(b.Intellect), action(key))

        _G.AURAS["player" .. ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT)] = true
        auras(ns)
        assert.are.same({}, action(key))

        -- The gem used up: its glow moves the key on with no aura event and no rebuild - the
        -- counts alone, as a cooldown update or a slider runs them - and back
        ITEMS[8008] = 0; ns.UpdateCounts()
        assert.is_true(b.ManaGem.antsShown)
        assert.are.same(clears(b.ManaGem, true), action(key))
        assert.are.equal("spell", key:GetAttribute("type1"))
        ITEMS[8008] = 1; ns.UpdateCounts()
        assert.are.same({}, action(key))

        -- The order decides between two glowing buttons; a hidden button does not count
        _G.AURAS = {}; ITEMS[8008] = 0; bags(); auras(ns)
        db.order = { "ManaGem", "Armor", "Intellect", "Water", "Food", "Teleport", "Portal" }
        ns.Rebuild()
        assert.are.same(clears(b.ManaGem, true), action(key))
        db.showGem = false; ns.Rebuild()
        assert.are.same(clears(b.Armor), action(key))
        ITEMS[8008] = 1
        assert.are.same({}, STATE.errors)
    end)

    it("keeps its action in combat, drops Intellect, and catches up when combat ends", function()
        local ns = login()
        local b, key = ns.buttons, _G[BUFF_KEY]
        _G.AURAS["player" .. ns.SpellName(ns.D.ARMOR_BUFF_IDS[1])] = true
        auras(ns)
        assert.are.same(clears(b.Intellect), action(key))

        STATE.combat = true; FIRE("PLAYER_REGEN_DISABLED")
        _G.STATE.casts = {}
        RUNCLICK(key, "LeftButton", false)
        assert.are.same({}, STATE.casts) -- Intellect is locked in combat

        -- A gem change in combat leaves the key as it was
        local writes = key.attrWrites
        ITEMS[8008] = 0; bags()
        assert.are.equal(writes, key.attrWrites)
        assert.are.same(clears(b.Intellect), action(key))

        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.are.same(clears(b.Intellect), action(key)) -- Intellect still comes before the gem
        _G.AURAS["player" .. ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT)] = true
        auras(ns)
        assert.are.same(clears(b.ManaGem, true), action(key))
        ITEMS[8008] = 1
        assert.are.same({}, STATE.errors)
    end)

    -- Michel, 2026-10-21: with nothing glowing when combat starts, the key casts Armor, as the
    -- button on the bar does; after combat it holds nothing again
    it("casts Armor in a combat that started with nothing glowing", function()
        local ns = login()
        local b, key = ns.buttons, _G[BUFF_KEY]
        _G.AURAS["player" .. ns.SpellName(ns.D.ARMOR_BUFF_IDS[1])] = true
        _G.AURAS["player" .. ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT)] = true
        auras(ns)
        assert.are.same({}, action(key))

        FIRE("PLAYER_REGEN_DISABLED") -- before the lockdown, as the client sends it
        STATE.combat = true
        assert.are.same(clears(b.Armor), action(key))
        _G.STATE.casts = {}
        RUNCLICK(key, "LeftButton", false)
        assert.are.same({ { spell = b.Armor:GetAttribute("spell1") } }, STATE.casts)

        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.are.same({}, action(key))
        assert.are.same({}, STATE.errors)
    end)

    it("casts Armor in combat, and takes an armor chosen there but not a teleport", function()
        local ns = login()
        local b, key = ns.buttons, _G[BUFF_KEY]
        assert.are.equal("Armor", key:GetAttribute("scbsource"))
        RUNCLICK(b.Armor, "RightButton", false) -- open the armor flyout before combat
        STATE.combat = true; FIRE("PLAYER_REGEN_DISABLED")

        local other = b.Armor.fly.buttons[2]
        assert.are_not.equal(other:GetAttribute("spell"), key:GetAttribute("spell1"))
        RUNCLICK(other, "LeftButton", false)
        assert.are.equal(other:GetAttribute("spell"), key:GetAttribute("spell1"))

        RUNCLICK(b.Teleport, "RightButton", false)
        RUNCLICK(b.Teleport.fly.buttons[1], "LeftButton", false)
        assert.are.equal(other:GetAttribute("spell"), key:GetAttribute("spell1"))

        _G.STATE.casts = {}
        RUNCLICK(key, "LeftButton", false)
        assert.are.same({ { spell = other:GetAttribute("spell") } }, STATE.casts)
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.are.same({}, STATE.errors)
    end)

    it("casts nothing in demo mode, and a press says once what it would cast", function()
        local ns, db = login()
        local key = _G[BUFF_KEY]
        db.demo = true; ns.Rebuild()
        assert.is_nil(key:GetAttribute("type1"))
        _G.CHAT, _G.STATE.casts = {}, {}
        RUNCLICK(key, "LeftButton", true)
        RUNCLICK(key, "LeftButton", false)
        assert.are.same({}, STATE.casts)
        assert.are.equal(1, #CHAT)
        db.demo = false; ns.Rebuild()
    end)
end)

describe("the settings key", function()
    it("opens and closes the window, and refuses in combat", function()
        local ns = login()
        local L = ns.L
        local key = _G[SETTINGS_KEY]
        SimpleConjureBarSettings:Hide()
        RUNCLICK(key, "LeftButton", false)
        assert.is_true(SimpleConjureBarSettings:IsShown())
        RUNCLICK(key, "LeftButton", false)
        assert.is_false(SimpleConjureBarSettings:IsShown())

        _G.CHAT = {}
        STATE.combat = true
        RUNCLICK(key, "LeftButton", false)
        assert.is_false(SimpleConjureBarSettings:IsShown())
        assert.is_truthy(CHAT[1] and CHAT[1]:find(L.MENU_COMBAT, 1, true))
        STATE.combat = false
    end)
end)

describe("the globals the addon writes", function()
    -- code.md's list: the saved variables, the slash commands, the compartment and binding
    -- names, and frames named SimpleConjureBar...
    local ALLOWED = {
        SimpleConjureBarDB = true, SimpleConjureBarGlobalDB = true, ConjureBarDB = true,
        SLASH_SIMPLECONJUREBAR1 = true, SLASH_SIMPLECONJUREBAR2 = true,
        SimpleConjureBar_OnCompartmentClick = true, SimpleConjureBar_OnCompartmentEnter = true,
        SimpleConjureBar_OnCompartmentLeave = true, BINDING_HEADER_SIMPLECONJUREBAR = true,
    }
    for name in pairs(BINDINGS) do ALLOWED["BINDING_NAME_" .. name] = true end

    -- Loads the addon as addon.load does, but each file in an environment that records every
    -- global it writes - also through _G[...], and also one an earlier load left in _G
    local function written(adjust)
        assert(loadfile("tests/helpers/mock.lua"))()
        STATE.locale = "enUS"
        _G.SimpleConjureBarDB = nil
        if adjust then adjust() end
        local seen = {}
        local env = setmetatable({}, {
            __index = _G,
            __newindex = function(_, k, v) seen[k] = true; _G[k] = v end,
        })
        rawset(env, "_G", env)
        local ns = {}
        for _, file in ipairs(addon.tocFiles()) do
            local chunk = assert(loadstring(addon.read("SimpleConjureBar/" .. file), "@" .. file))
            setfenv(chunk, env)
            chunk("SimpleConjureBar", ns)
        end
        FIRE("PLAYER_LOGIN"); RUNTIMERS()
        local new = {}
        for k in pairs(seen) do new[#new + 1] = k end
        return new
    end

    for _, case in ipairs({ { "a mage" }, { "another class", function()
        _G.UnitClass = function() return "Paladin", "PALADIN" end
    end } }) do
        it("as " .. case[1] .. ", only those on code.md's list", function()
            local new = written(case[2])
            for _, k in ipairs(new) do
                assert.is_true(ALLOWED[k] or k:match("^SimpleConjureBar") ~= nil, k)
            end
            assert.is_true(#new > 0)
        end)
    end
end)
