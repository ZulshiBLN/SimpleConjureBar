-- The flyout direction and auto-close (ruleset plan 2026-10-21-bar-alignment, item 4):
-- settings version 4, the direction applied to flyouts and arrows, the secure auto-hide.

local addon = require("addon")

local function login(saved, adjust)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS", adjust)
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

local function frames(frame, kind, found)
    found = found or {}
    for _, c in ipairs(frame.children) do
        if c.kind == kind then found[#found + 1] = c end
        frames(c, kind, found)
    end
    return found
end

-- The entries a dropdown's menu offers, with a function that picks each
local function entries(dd)
    local list = {}
    local root = { CreateRadio = function(_, text, _, pick)
        list[#list + 1] = { text = text, pick = pick }
    end }
    dd.menuFn(dd, root)
    return list
end

describe("settings version 4", function()
    it("adds the flyout direction and auto-close to a version 3 file, twice without change", function()
        local ns, db = login({ dbVersion = 3, scale = 1.2, antsSpeed = 4 })
        assert.are.equal(ns.D.DB_VERSION, db.dbVersion)
        assert.are.equal(4, ns.D.DB_VERSION)
        assert.are.equal("AUTO", db.flyoutDir)
        assert.are.equal(ns.D.VALUE_DEFAULTS.flyoutAutoClose, db.flyoutAutoClose)
        assert.are.equal(3, ns.D.VALUE_DEFAULTS.flyoutAutoClose)
        assert.are.same({ 1.2, 4 }, { db.scale, db.antsSpeed })
        db.flyoutDir, db.flyoutAutoClose = "SECOND", 2
        ns.InitDB()
        assert.are.same({ "SECOND", 2, 4 }, { db.flyoutDir, db.flyoutAutoClose, db.dbVersion })
    end)

    it("replaces a damaged direction or time", function()
        local _, db = login({ dbVersion = 4, flyoutDir = "UP", flyoutAutoClose = 9 })
        assert.are.same({ "AUTO", 5 }, { db.flyoutDir, db.flyoutAutoClose })
        _, db = login({ dbVersion = 4, flyoutDir = 7, flyoutAutoClose = "x" })
        assert.are.same({ "AUTO", 3 }, { db.flyoutDir, db.flyoutAutoClose })
        _, db = login({ dbVersion = 4, flyoutAutoClose = 0 })
        assert.are.equal(1, db.flyoutAutoClose)
    end)
end)

describe("the flyout direction", function()
    -- Where a flyout and its arrow sit against the main button, and the arrow's turn
    local function placed(main)
        local fp, _, frel = main.fly:GetPoint()
        local ap, _, arel = main.arrow:GetPoint()
        return { fp, frel, ap, arel, main.arrow.rotation }
    end

    it("opens to the chosen side, named by the orientation, and keeps the screen-half rule", function()
        local ns, db = login(nil)
        local armor = ns.buttons.Armor
        local UP    = { "BOTTOM", "TOP", "BOTTOM", "TOP", 0 }
        local DOWN  = { "TOP", "BOTTOM", "TOP", "BOTTOM", math.pi }
        local RIGHT = { "LEFT", "RIGHT", "LEFT", "RIGHT", -math.pi / 2 }
        local LEFT  = { "RIGHT", "LEFT", "RIGHT", "LEFT", math.pi / 2 }

        db.flyoutDir = "FIRST"; ns.Rebuild()
        assert.are.same(UP, placed(armor))
        assert.are.same(UP, placed(ns.buttons.Teleport))
        db.flyoutDir = "SECOND"; ns.Rebuild()
        assert.are.same(DOWN, placed(armor))
        db.vertical = true
        db.flyoutDir = "FIRST"; ns.Rebuild()
        assert.are.same(RIGHT, placed(armor))
        db.flyoutDir = "SECOND"; ns.Rebuild()
        assert.are.same(LEFT, placed(armor))

        -- Automatic: the bar's centre (500, 300) against the screen's halves
        db.vertical, db.flyoutDir = false, "AUTO"
        UIParent:SetSize(1000, 1000); ns.Rebuild()
        assert.are.same(UP, placed(armor))
        UIParent:SetSize(1000, 400); ns.Rebuild()
        assert.are.same(DOWN, placed(armor))
        db.vertical = true
        UIParent:SetSize(800, 1000); ns.Rebuild()
        assert.are.same(LEFT, placed(armor))
        UIParent:SetSize(1200, 1000); ns.Rebuild()
        assert.are.same(RIGHT, placed(armor))
        assert.are.same({}, STATE.errors)
    end)

    -- In game 2026-10-21: the bar dragged from the lower to the upper half kept opening its
    -- flyouts upwards - the direction was computed on a rebuild only, not after a drag
    it("follows a drag into the other half of the screen", function()
        local ns, db = login(nil)
        local armor = ns.buttons.Armor
        db.locked = false
        UIParent:SetSize(1000, 1000)
        ns.bar.GetCenter = function() return 500, 200 end
        ns.Rebuild()
        assert.are.equal(0, armor.arrow.rotation) -- lower half: up
        RUNSCRIPT(ns.handle, "OnMouseDown", "LeftButton")
        ns.bar.GetCenter = function() return 500, 800 end
        RUNSCRIPT(ns.handle, "OnMouseUp", "LeftButton")
        assert.are.equal(math.pi, armor.arrow.rotation) -- upper half: down
        assert.are.same({}, STATE.errors)
    end)

    it("is chosen on the General page, its entries named by the orientation", function()
        local ns, db = login(nil)
        local L = ns.L
        ns.ToggleSettings()
        local dd
        for _, d in ipairs(frames(SimpleConjureBarSettings, "DropdownButton")) do
            local e = entries(d)
            if e[1] and e[1].text == L.FLYDIR_AUTO then dd = d end
        end
        assert.is_not_nil(dd)
        local e = entries(dd)
        assert.are.same({ L.FLYDIR_AUTO, L.DIR_UP, L.DIR_DOWN }, { e[1].text, e[2].text, e[3].text })
        e[3].pick()
        assert.are.equal("SECOND", db.flyoutDir)
        db.vertical = true
        e = entries(dd)
        assert.are.same({ L.FLYDIR_AUTO, L.DIR_RIGHT, L.DIR_LEFT }, { e[1].text, e[2].text, e[3].text })
    end)
end)

describe("the flyout auto-close", function()
    it("closes a flyout once the mouse has left it and its button that long", function()
        local ns, db = login(nil)
        local armor, tele = ns.buttons.Armor, ns.buttons.Teleport
        assert.are.equal(db.flyoutAutoClose, ns.header:GetAttribute("autohide"))

        RUNCLICK(armor, "RightButton", false)
        assert.is_true(armor.fly:IsShown())
        assert.are.equal(3, armor.fly.autoHide)
        assert.are.same({ armor }, armor.fly.autoHideWith)

        -- Opening another flyout closes this one and ends its auto-hide
        RUNCLICK(tele, "RightButton", false)
        assert.is_false(armor.fly:IsShown())
        assert.is_nil(armor.fly.autoHide)
        assert.are.equal(3, tele.fly.autoHide)
        -- A second right click closes it
        RUNCLICK(tele, "RightButton", false)
        assert.is_false(tele.fly:IsShown())
        assert.is_nil(tele.fly.autoHide)

        -- A choice closes it too, also in combat
        RUNCLICK(armor, "RightButton", false)
        STATE.combat = true
        RUNCLICK(armor.fly.buttons[1], "LeftButton", false)
        STATE.combat = false
        assert.is_false(armor.fly:IsShown())
        assert.is_nil(armor.fly.autoHide)
        assert.are.same({}, STATE.errors)
    end)

    -- In game 2026-10-21 (1.1.0 test, BugSack 10x "Invalid frame handle"): no flyout opened in
    -- combat. A mage of level 25 knows no portal, so the Portal flyout held no secure button,
    -- was not protected, and the open snippet's handle to it was refused in combat.
    it("opens in combat while another flyout has no spell in it", function()
        -- The portal spells, from Data.lua, unknown from the start
        local data = {}
        assert(loadfile("SimpleConjureBar/Data.lua"))("SimpleConjureBar", data)
        local portals = {}
        for _, list in pairs(data.D.TRAVEL) do
            for _, d in ipairs(list) do portals[d.portal] = true end
        end
        local ns = login(nil, function()
            local known = C_SpellBook.IsSpellKnown
            C_SpellBook.IsSpellKnown = function(id) return not portals[id] and known(id) end
        end)
        local armor = ns.buttons.Armor
        assert.are.equal(0, #ns.buttons.Portal.fly.buttons)
        STATE.combat = true
        RUNCLICK(armor, "RightButton", false)
        assert.is_true(armor.fly:IsShown())
        assert.are.equal(3, armor.fly.autoHide)
        RUNCLICK(armor, "RightButton", false)
        assert.is_false(armor.fly:IsShown())
        STATE.combat = false
        assert.are.same({}, STATE.errors)
    end)

    it("takes its time from the slider at once", function()
        local ns, db = login(nil)
        ns.ToggleSettings()
        local found
        for _, s in ipairs(frames(SimpleConjureBarSettings, "Slider")) do
            local before = db.flyoutAutoClose
            s:SetValue(5)
            if db.flyoutAutoClose ~= before then found = s end
            if found then break end
        end
        assert.is_not_nil(found)
        assert.are.equal(5, ns.header:GetAttribute("autohide"))
        found:SetValue(1)
        assert.are.equal(1, ns.header:GetAttribute("autohide"))
        RUNCLICK(ns.buttons.Armor, "RightButton", false)
        assert.are.equal(1, ns.buttons.Armor.fly.autoHide)
    end)
end)
