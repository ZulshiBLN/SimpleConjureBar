-- "Show anchor": a check box that keeps the bar's handle visible; off, the handle shows only
-- while the mouse is over it, as before (ruleset plan 2026-10-21-toggle-anchor).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- The alpha the addon set; the mock's GetAlpha answers 1 when nothing was set
local function alpha(ns) return rawget(ns.handle, "alpha") end

-- What can happen to the handle, each ending with the mouse away from it
local function events(ns)
    local h = ns.handle
    return {
        login = function() end,
        ["mouse leaves"] = function()
            RUNSCRIPT(h, "OnEnter"); RUNSCRIPT(h, "OnLeave")
        end,
        ["drag ends"] = function()
            RUNSCRIPT(h, "OnMouseDown", "LeftButton"); RUNSCRIPT(h, "OnMouseUp", "LeftButton")
        end,
        ["/scb lock in combat"] = function()
            STATE.combat = true
            SlashCmdList.SIMPLECONJUREBAR("lock")
            STATE.combat = false
        end,
        -- PLAYER_REGEN_DISABLED comes before the lockdown, as in the client
        ["drag ended by combat start"] = function()
            RUNSCRIPT(h, "OnMouseDown", "LeftButton")
            FIRE("PLAYER_REGEN_DISABLED")
        end,
    }
end

describe("the handle", function()
    it("stays visible with Show anchor on, whatever happens to it", function()
        for name in pairs(events(login())) do
            local ns, db = login({ dbVersion = 4, showAnchor = true })
            db.locked = false
            events(ns)[name]()
            assert.are.equal(1, alpha(ns), name)
        end
    end)

    it("hides with Show anchor off once the mouse is away, and shows while it is over it", function()
        for name in pairs(events(login())) do
            local ns, db = login()
            db.locked = false
            events(ns)[name]()
            assert.are.equal(0, alpha(ns), name)
        end
        local ns, db = login()
        db.locked = false
        ns.handle.IsMouseOver = function() return true end
        events(ns)["drag ends"]()
        assert.are.equal(1, alpha(ns))
    end)
end)

-- A check box of the settings window by its label text
local function checkBox(label)
    local function find(frame)
        for _, c in ipairs(frame.children) do
            if c.kind == "CheckButton" then
                for _, r in ipairs(c.regions) do if r.text == label then return c end end
            end
            local hit = find(c)
            if hit then return hit end
        end
    end
    return find(SimpleConjureBarSettings)
end

describe("the Show anchor check box", function()
    it("sits beside Show border and shows or hides the handle at once", function()
        local ns, db = login()
        ns.ToggleSettings()
        local box, border = checkBox(ns.L.OPT_SHOW_ANCHOR), checkBox(ns.L.OPT_BORDER)
        assert.is_not_nil(box); assert.is_not_nil(border)
        assert.are.equal(border:GetParent(), box:GetParent())
        assert.is_false(box:GetChecked())

        box:SetChecked(true); RUNSCRIPT(box, "OnClick")
        assert.is_true(db.showAnchor)
        assert.are.equal(1, alpha(ns))
        box:SetChecked(false); RUNSCRIPT(box, "OnClick")
        assert.is_false(db.showAnchor)
        assert.are.equal(0, alpha(ns))
    end)
end)

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
