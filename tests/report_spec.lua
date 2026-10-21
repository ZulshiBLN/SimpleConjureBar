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

-- A BugGrabber as research found it on Forever (ruleset plan 2026-10-17-bug-report-details-
-- RESEARCH): GetDB and GetSessionId, no callback; entries with a Unix time and a session
local function grabber(errors, session)
    _G.BugGrabber = {
        GetDB = function() return errors end,
        GetSessionId = function() return session end,
    }
end

local function ourError(at, session, extra)
    local e = { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:10: attempt to index nil",
        stack = "[Interface/AddOns/SimpleConjureBar/Bar.lua]:10: in function 'x'", counter = 2,
        time = at, session = session, locals = "self=<table>" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

-- The report text, the window opened with a description, an area and details
local function report(ns, area, description, details)
    ns.OpenBugReport()
    local f = SimpleConjureBarReport
    if description then f.desc:SetText(description) end
    if details then f.details:SetText(details) end
    if area then f.SetArea(area) end
    return f.BuildText()
end

describe("the report form", function()
    it("carries the area key and both texts, and offers every area", function()
        local ns = login()
        grabber({}, 1)
        local text = report(ns, "TRAVEL", "Portal does nothing", "after the flyout closed")
        assert.is_truthy(text:find("**Area:** TRAVEL", 1, true), text)
        assert.is_truthy(text:find("Portal does nothing", 1, true))
        assert.is_truthy(text:find("after the flyout closed", 1, true))
        local offered = {}
        SimpleConjureBarReport.areaMenu.menuFn(nil, { CreateRadio = function(_, label) offered[#offered + 1] = label end })
        assert.are.equal(#ns.D.REPORT_AREAS, #offered)
        for i, key in ipairs(ns.D.REPORT_AREAS) do assert.are.equal(ns.L["AREA_" .. key], offered[i]) end
    end)

    it("dates nothing: times are relative to now and to the login", function()
        local ns = login()
        grabber({ ourError(time() - 90, 1) }, 1)
        local text = report(ns, "OTHER")
        assert.is_nil(text:find("%d%d%d%d%-%d%d%-%d%d"), text)
        assert.is_nil(text:find("%d%d:%d%d:%d%d"), text) -- no clock
        assert.is_nil(text:find("Date:", 1, true), text)
        assert.is_truthy(text:find("2 min ago", 1, true), text)
    end)

    it("says whether an error came in combat, and keeps earlier sessions out", function()
        local ns = login()
        STATE.now = STATE.now + 100
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        local inCombat = time()
        STATE.now = STATE.now + 10
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED")
        STATE.now = STATE.now + 100
        grabber({
            ourError(inCombat, 3, { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:1: in combat" }),
            ourError(time() - 5, 3, { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:2: out of combat" }),
            ourError(time() - 99999, 3, { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:3: before the log" }),
            ourError(time() - 50, 2, { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:4: earlier session" }),
        }, 3)
        local text = report(ns, "OTHER")
        local function flagOf(what)
            for block in text:gmatch("Error %d+ %b()") do
                local _, finish = text:find(block, 1, true)
                if text:sub(finish, finish + 200):find(what, 1, true) then return block:match("combat: (%a+)") end
            end
        end
        assert.are.equal("yes", flagOf("in combat"))
        assert.are.equal("no", flagOf("out of combat"))
        assert.are.equal("unknown", flagOf("before the log"))
        assert.is_nil(text:find("earlier session", 1, true))
    end)

    it("does not open in combat, closes when combat starts and comes back after it", function()
        local ns = login()
        grabber({}, 1)
        _G.CHAT = {}
        STATE.combat = true
        ns.OpenBugReport()
        assert.is_false(SimpleConjureBarReport:IsShown())
        assert.is_truthy(CHAT[#CHAT]:find(ns.L.REPORT_COMBAT, 1, true))
        STATE.combat = false
        ns.OpenBugReport()
        assert.is_true(SimpleConjureBarReport:IsShown())
        FIRE("PLAYER_REGEN_DISABLED")
        assert.is_false(SimpleConjureBarReport:IsShown())
        FIRE("PLAYER_REGEN_ENABLED")
        assert.is_true(SimpleConjureBarReport:IsShown())
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
