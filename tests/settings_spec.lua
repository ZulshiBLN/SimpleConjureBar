-- The settings window in every language: each dropdown is wide enough for its
-- longest entry. "简体中文 (Chinese S.)" was cut short at a fixed 180 px
-- (in-game checks, 2026-10-18). The entries are read from each dropdown's own
-- menu, the languages from Locales.lua, the room beside the text from Settings.lua.

local addon = require("addon")

-- Every dropdown under a frame, depth first.
local function dropdowns(frame, found)
    found = found or {}
    for _, child in ipairs(frame.children) do
        if child.kind == "DropdownButton" then found[#found + 1] = child end
        dropdowns(child, found)
    end
    return found
end

-- The entries a dropdown's menu offers, as its menu function builds them.
local function entries(dd)
    local texts = {}
    local root = { CreateRadio = function(_, text) texts[#texts + 1] = text end }
    dd.menuFn(dd, root)
    return texts
end

-- Width of a text as the mock measures it.
local function textWidth(text)
    local probe = NEWOBJ("FontString")
    probe:SetText(text)
    return probe:GetStringWidth()
end

describe("the settings window", function()
    local ns

    setup(function()
        ns = addon.load("enUS")
        FIRE("PLAYER_LOGIN")
        RUNTIMERS()
        ns.ToggleSettings()
    end)

    it("has dropdowns to check", function()
        assert.is_true(#dropdowns(SimpleConjureBarSettings) >= 4)
    end)

    it("makes every dropdown wide enough for its longest entry, in every language", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            ns.ApplyLanguage(code)
            for _, dd in ipairs(dropdowns(SimpleConjureBarSettings)) do
                for _, text in ipairs(entries(dd)) do
                    assert.is_true(textWidth(text) + ns.UI.DD_TEXT_PAD <= dd:GetWidth(),
                        code .. ": '" .. text .. "' does not fit in " .. dd:GetWidth() .. " px")
                end
            end
        end
    end)
end)
