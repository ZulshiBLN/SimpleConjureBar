-- The Macros tab's stopcasting macros and Ice Block macro (plan
-- 2026-10-17-mage-macros). Spell IDs come from Data.lua, never retyped.

local addon = require("addon")

-- A fresh client logging in with `saved` as the character's settings.
local function login(saved)
    local ns = addon.load("enUS")
    _G.SimpleConjureBarDB = saved
    FIRE("PLAYER_LOGIN")
    RUNTIMERS()
    return ns, SimpleConjureBarDB
end

describe("the chosen stopcasting spell", function()
    it("defaults to the first stopcasting spell", function()
        local ns, db = login(nil)
        assert.are.equal(ns.D.STOPCAST_SPELLS[1], db.macroStopcast)
    end)

    it("survives a reload when it is one of the stopcasting spells", function()
        local ns = addon.load("enUS")
        for _, id in ipairs(ns.D.STOPCAST_SPELLS) do
            local _, db = login({ macroStopcast = id })
            assert.are.equal(id, db.macroStopcast)
        end
    end)

    it("falls back to the first for another spell, a string or nothing", function()
        local ns = addon.load("enUS")
        for _, bad in ipairs({ ns.D.SPELL_ICE_BLOCK, 118, "2139", -1, 0 / 0 }) do
            local _, db = login({ macroStopcast = bad })
            assert.are.equal(ns.D.STOPCAST_SPELLS[1], db.macroStopcast, tostring(bad))
        end
    end)
end)
