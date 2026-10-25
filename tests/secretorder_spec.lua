-- A secret value errors when it is compared or truth-tested (rules/code.md, WoW Forever), so
-- `ns.IsSecret` must come first (ruleset plan 2026-10-25-report-filter-fixes, item 1, after
-- SmartBlessingBar's 38616ee). Lua 5.1 cannot trap `x == nil` or `if x`, and the mock's secrets
-- compare freely, so the first spec reads the source: in each region the first comparison or
-- truth test of the value comes after its secret check.

local addon = require("addon")

local function source(file)
    local f = assert(io.open("SimpleConjureBar/" .. file, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

-- The text from the first line holding `start` up to the first line after it matching `stop`
local function region(text, start, stop)
    local s = assert(text:find(start, 1, true), start)
    local pos = text:find("\n", s, true) + 1
    while true do
        local nl = text:find("\n", pos, true)
        local line = text:sub(pos, (nl or #text + 1) - 1)
        if line:find(stop) then return text:sub(s, nl or #text) end
        assert(nl, "no end for " .. start)
        pos = nl + 1
    end
end

-- Where `v` (a Lua pattern) is first compared or truth-tested in `text`, or nil
local function firstTest(text, v)
    local w = "%f[%w_%.]" .. v .. "%f[^%w_%.]"
    local best
    for _, p in ipairs({ w .. "%s*[=~]=", "[=~]=%s*" .. w, "if%s+" .. w, "not%s+" .. w,
                         "and%s+" .. w, "or%s+" .. w, w .. "%s+and", w .. "%s+or", w .. "%s+then",
                         "%(" .. w .. "%)%s+or" }) do
        local at = text:find(p)
        if at and (not best or at < best) then best = at end
    end
    return best
end

-- Where `v` is first passed to the secret check
local function firstCheck(text, v)
    return text:find("IsSecret%(" .. v .. "%)")
end

local function assertCheckedFirst(text, v, what)
    local test, check = firstTest(text, v), firstCheck(text, v)
    assert.is_truthy(check, what .. ": no secret check of " .. v)
    assert.is_true(test == nil or check < test, what .. ": " .. v .. " is tested before its secret check")
end

describe("secret values", function()
    it("are checked before they are compared or truth-tested", function()
        local privacy, trade, intellect = source("Privacy.lua"), source("Trade.lua"), source("Intellect.lua")
        local known = region(privacy, "function ns.KnownNames", "^end")
        assertCheckedFirst(region(known, "local function Add(v)", "^    end"), "v", "KnownNames' Add")
        local loop = region(known, "local name, realm = UnitName(u)", "^    end")
        assertCheckedFirst(loop, "name", "KnownNames' name and realm")
        assertCheckedFirst(loop, "realm", "KnownNames' name and realm")
        local fill = region(trade, "local function FillTrade", "^end")
        assertCheckedFirst(fill, "partner", "FillTrade")
        assertCheckedFirst(fill, "p%.guid", "FillTrade")
        assertCheckedFirst(region(intellect, "local function UnitShortName", "^end"), "name", "UnitShortName")
    end)

    it("fill no trade for a partner whose GUID is secret", function()
        _G.SimpleConjureBarDB = nil
        local ns = addon.load("enUS")
        FIRE("PLAYER_LOGIN"); RUNTIMERS()
        STATE.target = true
        _G.TRADE_SLOTS = {}
        RUNSCRIPT(ns.buttons.Water, "OnClick", "MiddleButton", false)
        STATE.tradeGuid = UnitGUID("target")
        STATE.secrets[STATE.tradeGuid] = true
        FIRE("TRADE_SHOW")
        assert.are.same({}, TRADE_SLOTS)
        assert.are.same({}, STATE.errors)
    end)

    it("name a member by his unit token while his name is secret", function()
        _G.SimpleConjureBarDB = nil
        local ns = addon.load("enUS")
        FIRE("PLAYER_LOGIN"); RUNTIMERS()
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 0 -- the single buff, on a member by name
        _G.AURAS["player" .. ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT)] = true -- not on yourself
        STATE.group, STATE.members = true, 2
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
        local b = ns.buttons.Intellect
        local unit = b:GetAttribute("unit1")
        STATE.secrets[UnitName(unit)] = true
        ns.UpdateBuffState()
        assert.is_truthy(b.hintLeft:find("> " .. unit, 1, true), b.hintLeft)
        assert.are.same({}, STATE.errors)
    end)
end)
