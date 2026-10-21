-- The TOC names the three AddOn compartment functions for every class, so the
-- client calls them on a non-mage too. They must exist there and do nothing.

local addon = require("addon")

local COMPARTMENT = {
    "SimpleConjureBar_OnCompartmentClick",
    "SimpleConjureBar_OnCompartmentEnter",
    "SimpleConjureBar_OnCompartmentLeave",
}

describe("the AddOn compartment on another class", function()
    it("exists, does nothing, and raises no error", function()
        local ns = addon.load("enUS", function()
            _G.UnitClass = function() return "Paladin", "PALADIN" end
            -- A mage loaded by another spec would have defined them already
            for _, name in ipairs(COMPARTMENT) do _G[name] = nil end
        end)
        FIRE("PLAYER_LOGIN")
        assert.is_false(ns.enabled)

        for _, name in ipairs(COMPARTMENT) do
            assert.are.equal("function", type(_G[name]), name)
        end
        local owners = 0
        GameTooltip.SetOwner = function() owners = owners + 1 end
        local ok, err = pcall(function()
            SimpleConjureBar_OnCompartmentClick("SimpleConjureBar", "LeftButton")
            SimpleConjureBar_OnCompartmentClick("SimpleConjureBar", "RightButton")
            SimpleConjureBar_OnCompartmentEnter("SimpleConjureBar", UIParent)
            SimpleConjureBar_OnCompartmentLeave("SimpleConjureBar", UIParent)
        end)
        assert.is_true(ok, err)
        assert.are.equal(0, owners, "no tooltip was shown")
        assert.is_nil(_G.SimpleConjureBarSettings, "no settings window was built")
        assert.are.same({}, STATE.errors)
    end)
end)
