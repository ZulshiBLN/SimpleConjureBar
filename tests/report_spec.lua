-- The bug report: everything needed to find and fix a bug without asking the player back, and
-- nothing about the player (ruleset plan 2026-10-17-bug-report-details).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

local function contains(lines, pattern)
    for _, l in ipairs(lines) do if l:find(pattern) then return l end end
end

describe("the state snapshot", function()
    it("lists every button with its click, the hidden buttons and a flyout child", function()
        local ns = login()
        ns.Rebuild(); RUNTIMERS()
        local lines = ns.StateSnapshot()
        for _, key in ipairs(ns.D.DEFAULT_ORDER) do
            assert.is_truthy(contains(lines, "^button " .. key .. " "), key)
        end
        local intel = contains(lines, "^button Intellect ")
        assert.is_truthy(intel:find("type1=spell", 1, true), intel)
        assert.is_truthy(intel:find("unit1=player", 1, true), intel)
        assert.is_truthy(contains(lines, "^button SimpleConjureBarBuffAll "))
        assert.is_truthy(contains(lines, "^button SimpleConjureBarBuffRun "))
        assert.is_truthy(contains(lines, "^button SimpleConjureBar_ArmorFlyout1 "))
        assert.is_truthy(contains(lines, "^keydown "))
        assert.is_truthy(contains(lines, "^combat no$"))
    end)

    it("counts the addon's items by ID, the group by class and own buffs with minutes left", function()
        local ns = login()
        local D = ns.D
        STATE.units.player = { auras = { { id = D.ARMOR_BUFF_IDS[1], expires = GetTime() + 600 }, 8098 } }
        STATE.units.party1 = { class = "PRIEST" }
        STATE.group, STATE.members = true, 2
        local lines = ns.StateSnapshot()
        assert.is_truthy(contains(lines, "^bags .*" .. D.ITEM_RUNE_TELE .. "=3"))
        assert.is_truthy(contains(lines, "^group party size=2 .*PRIEST=1"))
        local buffs = contains(lines, "^buffs ")
        assert.is_truthy(buffs:find(D.ARMOR_BUFF_IDS[1] .. ":10m", 1, true), buffs)
        assert.is_truthy(buffs:find("8098:-", 1, true), buffs)
    end)

    it("is what /scb debug prints", function()
        local ns = login()
        _G.CHAT = {}
        SlashCmdList.SIMPLECONJUREBAR("debug")
        local printed = table.concat(CHAT, "\n")
        for _, l in ipairs(ns.StateSnapshot()) do
            assert.is_truthy(printed:find(l, 1, true), l)
        end
    end)
end)

-- A press as the client delivers it: down, then up
local function press(button, mouse)
    RUNCLICK(button, mouse or "LeftButton", true)
    RUNCLICK(button, mouse or "LeftButton", false)
end

local function clicks(ns)
    local found = {}
    for _, l in ipairs(ns.LogLines()) do
        local what = l:match("^%S+ (click .*)$")
        if what then found[#found + 1] = what end
    end
    return found
end

describe("the action log", function()
    it("keeps one entry per press, with the key-down setting on and off", function()
        for _, keyDown in ipairs({ false, true }) do
            local ns = login()
            STATE.keyDown = keyDown
            press(ns.buttons.Water)
            press(ns.buttons.Intellect, "RightButton")
            local found = clicks(ns)
            assert.are.equal(2, #found, table.concat(found, " | "))
            assert.is_truthy(found[1]:find("^click Water LeftButton"))
            assert.is_truthy(found[2]:find("^click Intellect RightButton"))
            STATE.keyDown = nil
        end
    end)

    it("logs a left click on Intellect in a party with its spell and unit token", function()
        local ns = login()
        STATE.group, STATE.members = true, 3
        STATE.units.party2 = { class = "PRIEST" }
        STATE.units.player = { auras = { { id = ns.D.INTELLECT_RANKS[1].id, as = ns.D.SPELL_ARCANE_INTELLECT,
            expires = GetTime() + 3000 } } }
        STATE.units.party1 = STATE.units.player
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 0
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS(); ns.UpdateBuffState()
        press(ns.buttons.Intellect)
        local found = clicks(ns)
        local b = ns.buttons.Intellect
        assert.are.equal(("click Intellect LeftButton type=spell spell=%s unit=party2"):format(b:GetAttribute("spell1")),
            found[#found])
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 5
    end)

    it("logs a Buff & Run click as one Intellect and one hidden-button entry", function()
        local ns = login()
        STATE.units.target = { class = "PRIEST" }
        STATE.friends = { { class = "MAGE" } }
        press(ns.buttons.Intellect, "MiddleButton")
        local found = clicks(ns)
        assert.are.equal(2, #found, table.concat(found, " | "))
        -- the macro's nested click acts inside the Intellect click, so it is logged first
        assert.is_truthy(found[1]:find("^click SimpleConjureBarBuffRun LeftButton type=spell spell=%d+ unit=target"), found[1])
        assert.is_truthy(found[2]:find("^click Intellect MiddleButton"), found[2])
    end)

    it("holds the last 50 in order", function()
        local ns = login()
        for _ = 1, 60 do press(ns.buttons.Water) end
        local lines = ns.LogLines()
        assert.are.equal(50, #lines)
        local found = clicks(ns)
        assert.are.equal(50, #found)
    end)

    it("never stops a click when a log write fails", function()
        local ns = login()
        local clock = _G.time
        _G.time = function() error("broken clock") end -- every write reads it
        local before = #STATE.casts
        press(ns.buttons.Armor)
        assert.are.equal(before + 1, #STATE.casts)
        assert.are.same({}, STATE.errors)
        _G.time = clock
        -- and a line that cannot be formatted does not break the report
        ns.LogFormat = function() error("broken format") end
        assert.are.equal("?", ns.LogLines()[1])
    end)

    it("logs rebuilds, the buff key's source, Buff & Run's reason and changed settings", function()
        local ns, db = login()
        ns.Rebuild(); RUNTIMERS()
        assert.is_truthy(contains(ns.LogLines(), " rebuild$"))
        assert.is_truthy(contains(ns.LogLines(), " buffkey Armor$"))

        STATE.units.target = { class = "WARRIOR" }
        STATE.friends = { { class = "MAGE" } }
        press(ns.buttons.Intellect, "MiddleButton")
        assert.is_truthy(contains(ns.LogLines(), " buffrun none: no mana user$"))

        ns.ToggleSettings()
        db.armorRenewMinutes = 1
        ns.ToggleSettings()
        assert.is_truthy(contains(ns.LogLines(), " setting armorRenewMinutes=1$"))
        SlashCmdList.SIMPLECONJUREBAR("lock")
        assert.is_truthy(contains(ns.LogLines(), " setting locked=true$"))
    end)

    it("knows whether a moment was in combat", function()
        local ns = login()
        local t0 = time()
        assert.are.equal("no", ns.CombatAt(t0))
        assert.are.equal("unknown", ns.CombatAt(t0 - 3600))
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        assert.are.equal("yes", ns.CombatAt(time()))
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED")
        assert.is_truthy(contains(ns.LogLines(), "combat start"))
        assert.is_truthy(contains(ns.LogLines(), "combat end"))
    end)
end)

describe("the loaded addons", function()
    it("are listed by folder name and version, at most 60", function()
        local ns = login()
        _G.ADDONS = {}
        for i = 1, 65 do ADDONS[i] = { name = "Addon" .. i, title = "|cffff0000Addon " .. i .. "|r", loaded = i ~= 3 } end
        local lines = ns.AddonList()
        assert.are.equal(61, #lines) -- 60 and the count of the rest
        assert.are.equal("Addon1 1.0.0", lines[1])
        assert.is_nil(contains(lines, "^Addon3 "))
        assert.is_truthy(lines[61]:find("4 more", 1, true))
    end)
end)
