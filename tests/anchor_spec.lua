-- "Show anchor": a check box that keeps the bar's handle visible; off, the handle shows only
-- while the mouse is over it, as before (ruleset plan 2026-10-21-toggle-anchor).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

describe("the Show anchor setting", function()
    it("is off by default, a damaged value replaced, a saved one kept", function()
        local _, db = login()
        assert.is_false(db.showAnchor)
        _, db = login({ dbVersion = 4, showAnchor = "yes" })
        assert.is_false(db.showAnchor)
        _, db = login({ dbVersion = 4, showAnchor = true })
        assert.is_true(db.showAnchor)
    end)
end)
