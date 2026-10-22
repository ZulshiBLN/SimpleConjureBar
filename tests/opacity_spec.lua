-- The background of the settings and bug report windows, from invisible to solid (ruleset plan
-- 2026-10-22-window-opacity).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

describe("the window opacity setting", function()
    it("is today's look by default, a damaged value replaced, out of range clamped", function()
        local ns, db = login({ dbVersion = 3 })
        local D = ns.D
        assert.are.equal(D.WINDOW_OPACITY_TODAY, db.windowOpacity)
        assert.are.equal(D.VALUE_DEFAULTS.windowOpacity, D.WINDOW_OPACITY_TODAY)
        db = select(2, login({ dbVersion = 4, windowOpacity = "x" }))
        assert.are.equal(D.WINDOW_OPACITY_TODAY, db.windowOpacity)
        db = select(2, login({ dbVersion = 4, windowOpacity = 150 }))
        assert.are.equal(100, db.windowOpacity)
        db = select(2, login({ dbVersion = 4, windowOpacity = -5 }))
        assert.are.equal(0, db.windowOpacity)
    end)
end)
