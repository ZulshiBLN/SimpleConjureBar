-- Intellect and armor are renewed shortly before they run out, and a click with nothing to do
-- casts nothing (ruleset plan 2026-10-21-buff-renew).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- An Arcane Intellect of this rank with `minutes` left, answering to the spell's name
local function intellect(D, minutes, rank)
    return { id = rank or D.INTELLECT_RANKS[1].id, as = D.SPELL_ARCANE_INTELLECT, expires = GetTime() + minutes * 60 }
end

local function regroup(ns, group, raid, members)
    STATE.group, STATE.raid, STATE.members = group, raid, members
    FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
    ns.UpdateBuffState()
end

local function tooltipLines(ns)
    local lines = {}
    GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    ns.ShowTooltip(ns.buttons.Intellect)
    return lines
end

local function has(lines, wanted)
    for _, l in ipairs(lines) do if l == wanted then return true end end
    return false
end

describe("Arcane Intellect", function()
    it("solo casts nothing while it holds, and renews it within the renew time", function()
        local ns = login()
        local D, L, b = ns.D, ns.L, ns.buttons.Intellect
        STATE.units.player = { auras = { intellect(D, 10) } }
        ns.UpdateBuffState()
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_nil(b:GetAttribute("type2"))
        assert.is_false(b.antsShown)
        local lines = tooltipLines(ns)
        local nothing = L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1")) .. " > " .. L.EVERYONE_BUFFED)
        assert.is_true(has(lines, nothing), table.concat(lines, " | "))
        assert.is_true(has(lines, L.HINT_RIGHT:format(ns.SpellName(b:GetAttribute("spell2")) .. " > " .. L.EVERYONE_BUFFED)),
            table.concat(lines, " | "))

        STATE.units.player = { auras = { intellect(D, 4) } }
        ns.UpdateBuffState()
        assert.are.same({ "spell", "player" }, { b:GetAttribute("type1"), b:GetAttribute("unit1") })
        assert.is_true(b.antsShown)
        assert.are.equal("1", tostring(b.count:GetText()))

        SimpleConjureBarDB.intellectRenewMinutes = 0
        ns.UpdateBuffState()
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_false(b.antsShown)
    end)

    it("never renews a buff without expiry or one stronger than ours", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        STATE.units.player = { auras = { D.SPELL_ARCANE_INTELLECT } }
        ns.UpdateBuffState()
        assert.is_nil(b:GetAttribute("type1"))
        -- A level 10 priest takes rank 1 from us; another mage's top rank on him, 1 minute left,
        -- would refuse ours
        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST", level = 10, auras = { intellect(D, 1, D.INTELLECT_RANKS[1].id) } }
        regroup(ns, true, false, 2)
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_nil(b:GetAttribute("type2"))
    end)

    it("in a party buffs a missing member before an expiring one", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST", auras = { intellect(D, 1) } }
        STATE.units.party2 = { class = "PRIEST" }
        regroup(ns, true, false, 3)
        assert.are.equal("party2", b:GetAttribute("unit2")) -- the single buff, right click in a group
        assert.are.equal("2", tostring(b.count:GetText()))
    end)

    it("in a raid casts no Brilliance when no subgroup in need is in range", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        for i = 1, 5 do STATE.units["raid" .. i] = { auras = { intellect(D, 30) } } end
        STATE.units.raid6 = { class = "PRIEST", range = false } -- subgroup 2
        regroup(ns, true, true, 6)
        assert.are.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        assert.is_nil(b:GetAttribute("type1"))
        assert.are.equal("raid6", b:GetAttribute("unit2"))
        assert.are.same({}, STATE.errors)
    end)

    it("does not hide a missing armor from Cast next buff when its glowing click has nothing to do", function()
        local ns, db = login()
        local D = ns.D
        db.order = { "Intellect", "Armor", "ManaGem", "Water", "Food", "Teleport", "Portal" }
        for i = 1, 5 do STATE.units["raid" .. i] = { auras = { intellect(D, 30) } } end
        STATE.units.raid6 = { class = "PRIEST", range = false }
        regroup(ns, true, true, 6)
        assert.is_true(ns.buttons.Intellect.antsShown)
        assert.is_true(ns.buttons.Armor.antsShown)
        assert.are.equal("Armor", ns.buffKey:GetAttribute("scbsource"))
    end)

    it("is renewed by Buff & Run when expiring, and passed with time left", function()
        local ns = login()
        local D = ns.D
        STATE.units.target = { class = "PRIEST", auras = { intellect(D, 1, D.INTELLECT_RANKS[1].id) } }
        assert.are.equal(D.INTELLECT_RANKS[1].id, ns.BuffRunSpell("target"))
        STATE.units.target = { class = "PRIEST", auras = { intellect(D, 50, D.INTELLECT_RANKS[1].id) } }
        assert.is_nil(ns.BuffRunSpell("target"))
    end)
end)

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
