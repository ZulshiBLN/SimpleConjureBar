-- Chat speaks only in demo mode and as the answer to a chat command; a refused click is silent
-- (Michel's rule, ruleset plan 2026-10-25-chat-and-docked-report). Kept: auto-buy, the load and
-- migration lines, the trade lines.

local addon = require("addon")

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

local function said(ns, key)
    for _, line in ipairs(CHAT) do
        if line:find(ns.L[key], 1, true) then return true end
    end
    return false
end

describe("the chat", function()
    it("stays silent for every click or key refused in combat", function()
        local ns, db = login()
        db.locked = false
        SimpleConjureBarSettings:Hide()
        _G.CHAT = {}
        STATE.combat = true
        RUNSCRIPT(ns.handle, "OnMouseDown", "LeftButton")      -- drag
        RUNSCRIPT(ns.handle, "OnMouseDown", "MiddleButton")    -- settings
        RUNSCRIPT(SimpleConjureBarMinimapButton, "OnClick", "LeftButton")
        RUNCLICK(_G.SimpleConjureBarSettingsKey, "LeftButton", false)
        ns.CreateIceBlockMacro()
        ns.ShowMacroWindow()
        ns.OpenBugReport() -- the settings' "Report bug" button
        STATE.combat = false
        assert.are.same({}, CHAT)
    end)

    it("says why for a chat command in combat, and stays silent for a click after it", function()
        local ns = login()
        SimpleConjureBarSettings:Hide()
        _G.CHAT = {}
        STATE.combat = true
        SlashCmdList.SIMPLECONJUREBAR("")
        assert.are.equal(1, #CHAT)
        assert.is_true(said(ns, "MENU_COMBAT"))
        RUNSCRIPT(ns.handle, "OnMouseDown", "MiddleButton")
        assert.are.equal(1, #CHAT)
        SlashCmdList.SIMPLECONJUREBAR("bug")
        assert.are.equal(2, #CHAT)
        assert.is_true(said(ns, "REPORT_COMBAT"))
        STATE.combat = false
    end)

    it("leaves the lock to the tooltip: no chat line, and the menu entry's tooltip redrawn", function()
        local ns, db = login()
        _G.CHAT = {}
        local right
        GameTooltip.AddLine = function(_, text)
            if text == ns.L.HINT_RIGHT:format(ns.L.LOCK_BAR) then right = ns.L.LOCK_BAR end
            if text == ns.L.HINT_RIGHT:format(ns.L.UNLOCK_BAR) then right = ns.L.UNLOCK_BAR end
        end
        local entry = NEWOBJ("Frame", "menuEntry")
        db.locked = false
        ns.CompartmentEnter(nil, entry)
        right = nil
        ns.CompartmentClick(nil, "RightButton", nil) -- the client passes no frame
        assert.is_true(db.locked)
        assert.are.equal(ns.L.UNLOCK_BAR, right)
        RUNSCRIPT(SimpleConjureBarMinimapButton, "OnClick", "RightButton")
        assert.is_false(db.locked)
        assert.are.same({}, CHAT)
    end)

    it("shows a macro's result in the Macros tab for 8 seconds, not in the chat", function()
        local ns = login()
        _G.MACROS = {}
        _G.CHAT = {}
        ns.CreateIceBlockMacro()
        assert.are.same({}, CHAT)
        local line = ns.MacroResultLine
        assert.is_true(line:IsShown())
        assert.is_truthy(line:GetText():find("SCB", 1, true), line:GetText())
        ADVANCE(5)
        ns.CreateIceBlockMacro() -- a second result replaces the first and its timer
        ADVANCE(5)
        assert.is_true(line:IsShown())
        ADVANCE(4)
        assert.is_false(line:IsShown())
        assert.are.same({}, STATE.errors)
    end)

    it("leaves room for the longest macro result in two lines beside Show macro", function()
        for _, locale in ipairs({ "enUS", "frFR", "ruRU", "deDE" }) do
            _G.SimpleConjureBarDB = nil
            local ns = addon.load(locale)
            FIRE("PLAYER_LOGIN"); RUNTIMERS()
            ns.ToggleSettings()
            local L, line = ns.L, ns.MacroResultLine
            local name = ("W"):rep(16)
            local longest = 0
            for _, text in ipairs({ L.MACRO_CREATED:format(name), L.MACRO_UPDATED:format(name), L.MACRO_FULL }) do
                line:SetText(text)
                longest = math.max(longest, line:GetStringWidth())
            end
            local room = SimpleConjureBarSettings:GetWidth() - 2 * 22 - ns.MacroShowButton:GetWidth() - 8
            assert.is_true(longest <= 2 * room, locale .. ": " .. longest .. " > 2 x " .. room)
            ns.ToggleSettings()
        end
    end)
end)
