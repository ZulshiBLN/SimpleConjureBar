-- Guards that every spec passed by before: removing one left the suite green (found by
-- SmartBlessingBar's 1.1.0 review, F-05, and checked in SCB by mutation, 2026-10-26).

local addon = require("addon")

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns
end

describe("the guards", function()
    -- Michel, 2026-10-26: SetAttr itself refuses in combat, as SmartBlessingBar's does
    it("write no secure attribute in combat", function()
        local ns = login()
        local b = ns.buttons.Intellect
        local before = b:GetAttribute("spell1")
        STATE.combat = true
        ns.SetAttr(b, "spell1", 424242)
        assert.are.equal(before, b:GetAttribute("spell1"))
        assert.are.same({}, STATE.errors)
        STATE.combat = false
        ns.SetAttr(b, "spell1", 424242)
        assert.are.equal(424242, b:GetAttribute("spell1"))
    end)

    it("keep the action log's last 50 in order once it wraps", function()
        local ns = login()
        for i = 1, 60 do ns.Log("entry " .. i) end
        local lines = ns.LogLines()
        assert.are.equal(50, #lines)
        assert.is_truthy(lines[1]:find("entry 11$"), lines[1])
        assert.is_truthy(lines[50]:find("entry 60$"), lines[50])
    end)
end)
