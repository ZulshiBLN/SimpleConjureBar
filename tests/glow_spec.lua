-- The highlight of Armor, Intellect and Mana Gem: the modern client's proc glow, a looping
-- flipbook tinted by each button's colour, its speed from the button's slider
-- (ruleset plan 2026-10-21-bar-alignment, item 1).

local addon = require("addon")

-- Each glowing button with its colour and speed setting
local GLOWS = {
    { "Armor",     "armorAntsColor", "armorAntsSpeed" },
    { "Intellect", "antsColor",      "antsSpeed" },
    { "ManaGem",   "gemAntsColor",   "gemAntsSpeed" },
}

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- Every slider below a frame
local function sliders(frame, found)
    found = found or {}
    for _, c in ipairs(frame.children) do
        if c.kind == "Slider" then found[#found + 1] = c end
        sliders(c, found)
    end
    return found
end

describe("the glow", function()
    it("is the client's proc flipbook, sized, centred and tinted per button", function()
        local ns, db = login()
        local D = ns.D
        for _, g in ipairs(GLOWS) do
            local b, col = ns.buttons[g[1]], db[g[2]]
            assert.are.equal(D.GLOW_ATLAS, b.ants.atlas, g[1])
            assert.are.equal("UI-HUD-ActionBar-Proc-Loop-Flipbook", D.GLOW_ATLAS)
            assert.are.same({ b:GetWidth() * D.GLOW_SCALE, b:GetHeight() * D.GLOW_SCALE },
                { b.ants:GetWidth(), b.ants:GetHeight() }, g[1])
            assert.are.equal(1.4, D.GLOW_SCALE)
            assert.are.same({ "CENTER" }, { b.ants:GetPoint() }, g[1])
            assert.are.same({ col.r, col.g, col.b, col.a }, b.ants.vertexColor, g[1])
            assert.are.equal("REPEAT", b.antsAnim.looping, g[1])
            local flip = b.antsFlip
            assert.are.same({ "FlipBook", 6, 5, 30 }, { flip.kind, flip.rows, flip.columns, flip.frames }, g[1])
            assert.are.equal(D.GLOW_DURATIONS[db[g[3]]], flip:GetDuration(), g[1])
        end
        assert.are.same({}, STATE.errors)
    end)

    it("plays only while it is shown", function()
        local ns = login()
        local b = ns.buttons
        -- Solo, no armor and no Intellect on the player, a gem in the bags
        assert.is_true(b.Armor.ants:IsShown() and b.Armor.antsAnim:IsPlaying())
        assert.is_true(b.Intellect.ants:IsShown() and b.Intellect.antsAnim:IsPlaying())
        assert.is_false(b.ManaGem.ants:IsShown() or b.ManaGem.antsAnim:IsPlaying())

        ns.SetAnts(b.Intellect, false)
        assert.is_false(b.Intellect.ants:IsShown() or b.Intellect.antsAnim:IsPlaying())
        ns.SetAnts(b.ManaGem, true)
        assert.is_true(b.ManaGem.ants:IsShown() and b.ManaGem.antsAnim:IsPlaying())
    end)

    it("follows each speed slider at once, and only its own button", function()
        local ns, db = login()
        local D = ns.D
        assert.are.equal(1, D.GLOW_DURATIONS[3]) -- the default is Blizzard's second
        SlashCmdList.SIMPLECONJUREBAR("")
        local found = 0
        for _, s in ipairs(sliders(SimpleConjureBarSettings)) do
            local before = {}
            for _, g in ipairs(GLOWS) do before[g[3]] = db[g[3]] end
            s:SetValue(5)
            for _, g in ipairs(GLOWS) do
                if db[g[3]] ~= before[g[3]] then
                    found = found + 1
                    assert.are.equal(D.GLOW_DURATIONS[5], ns.buttons[g[1]].antsFlip:GetDuration(), g[1])
                    for _, other in ipairs(GLOWS) do
                        if other ~= g then
                            assert.are.equal(D.GLOW_DURATIONS[db[other[3]]],
                                ns.buttons[other[1]].antsFlip:GetDuration(), other[1])
                        end
                    end
                    s:SetValue(1)
                    assert.are.equal(D.GLOW_DURATIONS[1], ns.buttons[g[1]].antsFlip:GetDuration(), g[1])
                end
            end
        end
        assert.are.equal(#GLOWS, found)
        assert.are.same({}, STATE.errors)
    end)
end)
