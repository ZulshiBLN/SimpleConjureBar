-- The background of the settings and bug report windows, from invisible to solid (ruleset plan
-- 2026-10-22-window-opacity).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- The two alphas the plan's formulas give for an opacity in percent
local function expected(D, percent)
    local o, d = percent / 100, D.WINDOW_OPACITY_TODAY / 100
    return math.min(1, o / d), math.max(0, (o - d) / (1 - d))
end

local function checkWindow(D, window, percent, name)
    local texture, layer = expected(D, percent)
    assert.near(texture, window.backdropColor[4], 1e-9, name .. " texture at " .. percent)
    assert.near(layer, window.opacityLayer:GetAlpha(), 1e-9, name .. " layer at " .. percent)
    assert.is_true(window.opacityLayer.sublevel < window.Center.sublevel, name .. ": the black layer below")
    assert.are.equal(1, window:GetAlpha(), name .. ": the window itself")
end

describe("the window background", function()
    it("follows the formulas in both windows, below the texture, the windows themselves untouched", function()
        local ns, db = login()
        local D = ns.D
        ns.ToggleSettings()
        ns.OpenBugReport()
        local settings, report = SimpleConjureBarSettings, SimpleConjureBarReport
        local borders = { settings.borderColor, report.borderColor }
        for _, percent in ipairs({ 0, 30, D.WINDOW_OPACITY_TODAY, 80, 100 }) do
            db.windowOpacity = percent
            ns.ApplyWindowOpacities()
            checkWindow(D, settings, percent, "settings")
            checkWindow(D, report, percent, "report")
        end
        assert.are.same(borders, { settings.borderColor, report.borderColor })
    end)

    it("reaches a report opened after the value changed", function()
        local ns, db = login()
        ns.OpenBugReport()
        SimpleConjureBarReport:Hide()
        db.windowOpacity = 20
        ns.ApplyWindowOpacities()
        db.windowOpacity = 90 -- changed while the report is closed, as the slider may
        ns.ToggleSettings(); ns.ApplyWindowOpacity(SimpleConjureBarSettings)
        ns.OpenBugReport()
        checkWindow(ns.D, SimpleConjureBarReport, 90, "report")
    end)
end)

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
