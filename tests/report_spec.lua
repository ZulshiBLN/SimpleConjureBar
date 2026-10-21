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

    it("names the chosen area in the language just switched to", function()
        local ns = login()
        grabber({}, 1)
        ns.OpenBugReport()
        local menu = SimpleConjureBarReport.areaMenu
        assert.are.equal(ns.locales.enUS.AREA_OTHER, menu.selectedText)
        for _, code in ipairs({ "ruRU", "koKR", "zhCN" }) do
            ns.ApplyLanguage(code)
            assert.are.equal(ns.locales[code].AREA_OTHER, menu.selectedText, code)
        end
        SimpleConjureBarReport.SetArea("TRAVEL")
        assert.are.equal(ns.locales.zhCN.AREA_TRAVEL, menu.selectedText)
    end)

    it("opens beside the open settings window, which stays open, and goes with it", function()
        local ns = login()
        grabber({}, 1)
        ns.ToggleSettings()
        local settings = SimpleConjureBarSettings
        ns.OpenBugReport()
        local window = SimpleConjureBarReport
        assert.is_true(settings:IsShown())
        assert.is_true(window:IsShown())
        local point, relativeTo, relativePoint = window:GetPoint()
        assert.are.equal("TOPRIGHT", point)
        assert.are.equal(settings, relativeTo)
        assert.are.equal("TOPLEFT", relativePoint)
        settings:Hide()
        assert.is_false(window:IsShown())

        -- without the settings window: in the middle of the screen, as before
        ns.OpenBugReport()
        assert.is_true(window:IsShown())
        assert.are.equal("CENTER", (window:GetPoint()))
        ns.ToggleSettings() -- opening the settings later leaves the report where it is
        settings:Hide()
        assert.is_true(window:IsShown())
    end)

    it("comes back with the settings after combat when docked to them", function()
        local ns = login()
        grabber({}, 1)
        ns.ToggleSettings()
        ns.OpenBugReport()
        local settings, window = SimpleConjureBarSettings, SimpleConjureBarReport
        -- PLAYER_REGEN_DISABLED: the player is in combat, the lockdown not yet
        STATE.affecting = true
        FIRE("PLAYER_REGEN_DISABLED")
        assert.is_false(settings:IsShown())
        assert.is_false(window:IsShown())
        STATE.affecting = false
        FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_true(settings:IsShown())
        assert.is_true(window:IsShown())
        -- closed by hand, the settings take the report along, and it stays closed
        settings:Hide()
        FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_false(window:IsShown())
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
        FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_true(SimpleConjureBarReport:IsShown())
    end)
end)

-- Every byte sequence a whole UTF-8 character
local function validUtf8(s)
    local i = 1
    while i <= #s do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC0 and 2 or 0
        if len == 0 or i + len - 1 > #s then return false end
        for k = i + 1, i + len - 1 do
            local b = s:byte(k)
            if b < 0x80 or b > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

-- Made-up values only (CLAUDE.md, secrets): none of them may reach a report
local POISON = {
    "Testplayer", "Testrealm", "Testguild", "Partyone", "partyone", "Tèstname", "Targetguy",
    "Player-1111-0AAAAAAA", "Somebody#1234", "C:\\Users\\someone", "Lockeduser", "/Users/macsomeone",
    "/home/linuxsomeone",
}

local function poisonedClient()
    _G.GetRealmName = function() return "Testrealm" end
    _G.GetNormalizedRealmName = function() return "Testrealm" end
    _G.GetGuildInfo = function() return "Testguild" end
end

local function poison(db)
    STATE.units.player = { name = "Testplayer" }
    STATE.units.party1 = { name = "Partyone", class = "PRIEST" }
    STATE.units.party2 = { name = "Tèstname", class = "DRUID" }
    STATE.units.target = { name = "Targetguy" }
    STATE.group, STATE.members = true, 3
    db.someString = "Partyone"           -- an unknown string setting
    db.flyoutDir = "Lockeduser"          -- a known key with a damaged value
    grabber({ ourError(time(), 1, {
        message = "Interface/AddOns/SimpleConjureBar/Bar.lua:10: Testplayer-Testrealm said partyone and Tèstname Player-1111-0AAAAAAA Somebody#1234",
        stack = "[C:\\Users\\someone\\Interface\\AddOns\\SimpleConjureBar\\Bar.lua]:10: in function 'Targetguy'",
        locals = table.concat({
            'name="Partyone"', "self=<table> {", '  Partyone = 1', '  [1] = "Targetguy"',
            '  frame = Testguild {', "  }", "}", 'count=3', 'flag=true', 'unit="party1"',
            'Somebody#1234 = 5', "not a line we can read",
        }, "\n"),
    }) }, 1)
end

describe("the report's privacy", function()
    it("lets no name, GUID, tag or path through, and every line is a listed field", function()
        local ns, db
        ns, db = login(nil)
        poisonedClient()
        poison(db)
        local text = report(ns, "OTHER", "Partyone and Testplayer-Testrealm broke it", "with Targetguy, see C:\\Users\\someone\\x, /Users/macsomeone/wow and /home/linuxsomeone/wow")
        for _, bad in ipairs(POISON) do
            assert.is_nil(text:find(bad, 1, true), bad .. " leaked:\n" .. text)
        end
        -- what the developer needs is still there
        assert.is_truthy(text:find("<name>", 1, true))
        assert.is_truthy(text:find("<guid>", 1, true))
        assert.is_truthy(text:find("<tag>", 1, true))
        -- the stack line keeps its file, cut to the addons folder
        assert.is_truthy(text:find("at [Interface/AddOns/SimpleConjureBar/Bar.lua]:10:", 1, true), text)
        assert.is_truthy(text:find("local count=3", 1, true), text)
        assert.is_truthy(text:find('local unit="party1"', 1, true), text)
        -- every line belongs to a field of the list
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local known = false
            for _, f in ipairs(ns.D.REPORT_FIELDS) do
                if line:find(f.pattern) then known = true break end
            end
            assert.is_true(known, "not a listed field: " .. line)
        end
    end)

    it("keeps the window shut while a name is secret", function()
        local ns = login()
        grabber({}, 1)
        STATE.units.target = { name = "Targetguy" }
        _G.issecretvalue = function(v) return v == "Targetguy" end
        _G.CHAT = {}
        ns.OpenBugReport()
        assert.is_false(SimpleConjureBarReport:IsShown())
        assert.is_truthy(CHAT[#CHAT]:find(ns.L.REPORT_SECRET, 1, true))
        _G.issecretvalue = nil
    end)

    it("builds nothing new while a name turns secret after the window opened", function()
        local ns, db
        ns, db = login(nil)
        poisonedClient()
        poison(db)
        ns.OpenBugReport()
        local f = SimpleConjureBarReport
        local before = f.report:GetText()
        _G.issecretvalue = function(v) return v == "Targetguy" end
        _G.CHAT = {}
        f.desc:SetText("Testplayer saw it"); RUNSCRIPT(f.desc, "OnTextChanged", true)
        assert.are.equal(before, f.report:GetText())
        assert.is_nil((ns.ReportCode.Decode(f.report:GetText()) or ""):find("Testplayer", 1, true))
        assert.is_truthy(CHAT[#CHAT]:find(ns.L.REPORT_SECRET, 1, true))
        _G.issecretvalue = nil
    end)

    it("stays under 20,000 bytes, cut at a whole character, and shows the data list", function()
        local ns = login()
        local errors = {}
        for i = 1, 5 do
            local lines = {}
            for j = 1, 200 do lines[j] = ("v%d=%d"):format(j, j) end
            errors[i] = ourError(time(), 1, { message = ("Interface/AddOns/SimpleConjureBar/Bar.lua:%d: %s"):format(i, ("ü"):rep(2000)),
                locals = table.concat(lines, "\n") })
        end
        grabber(errors, 1)
        local text = report(ns, "OTHER", ("ä"):rep(500), ("ö"):rep(500))
        assert.is_true(#text <= 20000, #text)
        assert.is_truthy(text:find(ns.D.REPORT_CUT, 1, true))
        assert.is_true(validUtf8(text))
        local f = SimpleConjureBarReport
        local function shown(key)
            for _, r in ipairs(f.regions) do if r.text == ns.L[key] then return true end end
        end
        assert.is_true(shown("REPORT_PRIVACY"))
        assert.is_true(shown("REPORT_PUBLIC"))
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
