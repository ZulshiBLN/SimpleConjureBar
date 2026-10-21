-- Intellect and armor are renewed shortly before they run out, and a click with nothing to do
-- casts nothing (ruleset plan 2026-10-21-buff-renew).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

describe("the renew times", function()
    it("are in settings version 4 with their defaults, clamped and kept", function()
        local ns, db = login({ dbVersion = 3 })
        local D = ns.D
        assert.are.same({ D.VALUE_DEFAULTS.intellectRenewMinutes, D.VALUE_DEFAULTS.armorRenewMinutes },
            { db.intellectRenewMinutes, db.armorRenewMinutes })
        assert.are.same({ 5, 3 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        db = select(2, login({ dbVersion = 4, intellectRenewMinutes = "x", armorRenewMinutes = "x" }))
        assert.are.same({ 5, 3 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        db = select(2, login({ dbVersion = 4, intellectRenewMinutes = 99, armorRenewMinutes = 99 }))
        assert.are.same({ D.INTELLECT_RENEW_MAX, D.ARMOR_RENEW_MAX }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        db = select(2, login({ dbVersion = 4, intellectRenewMinutes = -1, armorRenewMinutes = -1 }))
        assert.are.same({ 0, 0 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        -- twice without change
        local saved = { dbVersion = 4, intellectRenewMinutes = 7, armorRenewMinutes = 2 }
        db = select(2, login(saved))
        db = select(2, login(db))
        assert.are.same({ 7, 2 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
    end)
end)
