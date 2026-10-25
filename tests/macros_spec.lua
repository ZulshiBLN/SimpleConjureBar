-- The Macros tab's stopcasting macros and Ice Block macro (plan
-- 2026-10-17-mage-macros). Spell IDs come from Data.lua, never retyped.

local addon = require("addon")

-- A fresh client logging in with `saved` as the character's settings.
local function login(saved, adjust)
    local ns = addon.load("enUS", adjust)
    _G.SimpleConjureBarDB = saved
    FIRE("PLAYER_LOGIN")
    RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- The lines of a macro body.
local function lines(body)
    local t = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = line end
    return t
end

-- Number of UTF-8 characters, or nil when the string is not valid UTF-8.
local function utf8Length(s)
    local n, rest = 0, s
    while #rest > 0 do
        local ch = rest:match("^[%z\1-\127]") or rest:match("^[\194-\223][\128-\191]")
            or rest:match("^[\224-\239][\128-\191][\128-\191]")
            or rest:match("^[\240-\244][\128-\191][\128-\191][\128-\191]")
        if not ch then return nil end
        n, rest = n + 1, rest:sub(#ch + 1)
    end
    return n
end

describe("the new macros", function()
    local ns

    before_each(function()
        ns = login(nil)
        _G.MACROS = {}
        _G.CHAT = {}
    end)

    -- Every macro the five buttons can create, with the lines the plan names.
    -- Spell names come from the mocked client, so they are read the same way.
    local function cases()
        local D, name = ns.D, ns.SpellName
        local list = {
            { create = ns.CreateIceBlockMacro, spell = D.SPELL_ICE_BLOCK, body = {
                "#showtooltip " .. name(D.SPELL_ICE_BLOCK),
                "/cancelaura " .. name(D.SPELL_ICE_BLOCK),
                "/cast " .. name(D.SPELL_ICE_BLOCK) } },
        }
        for _, id in ipairs(D.STOPCAST_SPELLS) do
            local target = (id == D.SPELL_COUNTERSPELL) and "[@focus,harm,nodead][] " or ""
            list[#list + 1] = { create = function() ns.CreateStopcastMacro(id) end, spell = id, body = {
                "#showtooltip " .. name(id), "/stopcasting", "/cast " .. target .. name(id) } }
        end
        return list
    end

    it("creates one character macro per spell with exactly the planned lines", function()
        for _, case in ipairs(cases()) do
            _G.MACROS = {}
            case.create()
            assert.are.equal(1, #MACROS, case.spell)
            assert.are.equal("SCB " .. ns.SpellName(case.spell), MACROS[1].name)
            assert.is_true(MACROS[1].perChar)
            assert.are.same(case.body, lines(MACROS[1].body), case.spell)
        end
    end)

    it("aims only Counterspell at the focus", function()
        for _, case in ipairs(cases()) do
            local aims = case.body[3]:find("@focus", 1, true) ~= nil
            assert.are.equal(case.spell == ns.D.SPELL_COUNTERSPELL, aims, case.spell)
        end
        for _, id in ipairs(ns.D.STOPCAST_SPELLS) do
            _G.MACROS = {}
            ns.CreateStopcastMacro(id)
            assert.are.equal(id == ns.D.SPELL_COUNTERSPELL,
                MACROS[1].body:find("[@focus,harm,nodead]", 1, true) ~= nil, id)
        end
    end)

    it("updates a macro on the second click instead of adding one", function()
        for _, case in ipairs(cases()) do
            _G.MACROS = {}
            case.create()
            MACROS[1].body = "old"
            case.create()
            assert.are.equal(1, #MACROS, case.spell)
            assert.are_not.equal("old", MACROS[1].body)
        end
    end)

    -- code review 1.1.0, F-15: the account-wide macro was found first, so each click added
    -- another character copy
    it("leaves a player's account-wide macro of the same name alone and adds one copy", function()
        for _, case in ipairs(cases()) do
            local name = "SCB " .. ns.SpellName(case.spell)
            _G.MACROS = { { name = name, body = "mine" } }
            case.create()
            case.create()
            assert.are.equal(2, #MACROS, case.spell)
            assert.are.same({ name, "mine" }, { MACROS[1].name, MACROS[1].body })
            assert.is_true(MACROS[2].perChar)
        end
        -- The unpublished 1.33's account-wide "SCB Polymorph" is still replaced
        _G.MACROS = { { name = "SCB Polymorph", body = "old" } }
        ns.CreatePolymorphMacro()
        ns.CreatePolymorphMacro()
        assert.are.equal(1, #MACROS)
        assert.is_true(MACROS[1].perChar)
    end)

    it("uses the chosen stopcasting spell when none is given", function()
        SimpleConjureBarDB.macroStopcast = ns.D.STOPCAST_SPELLS[3]
        ns.CreateStopcastMacro()
        assert.are.equal("SCB " .. ns.SpellName(ns.D.STOPCAST_SPELLS[3]), MACROS[1].name)
    end)

    it("cuts a long Cyrillic name to 16 whole characters", function()
        local cyrillic = "Ледяная глыба" -- 13 letters
        local iceBlock = ns.D.SPELL_ICE_BLOCK
        local fresh = login(nil, function()
            local original = C_Spell.GetSpellName
            C_Spell.GetSpellName = function(id)
                if id == iceBlock then return cyrillic end
                return original(id)
            end
        end)
        _G.MACROS = {}
        fresh.CreateIceBlockMacro()
        local name = MACROS[1].name
        assert.are.equal(16, utf8Length(name), name)
        assert.are.equal("SCB Ледяная глыб", name)
        assert.are.equal("/cast " .. cyrillic, lines(MACROS[1].body)[3])
    end)

    -- The result shows in the Macros tab, not the chat (ruleset plan
    -- 2026-10-25-chat-and-docked-report)
    it("creates nothing without a free character slot, and says so in the window", function()
        for i = 1, (MAX_CHARACTER_MACROS or 18) do
            MACROS[#MACROS + 1] = { name = "M" .. i, body = "", perChar = true }
        end
        local before = #MACROS
        ns.CreateIceBlockMacro()
        ns.CreateStopcastMacro(ns.D.STOPCAST_SPELLS[1])
        assert.are.equal(before, #MACROS)
        assert.are.equal(ns.L.MACRO_FULL, ns.MacroResultLine:GetText())
        assert.are.same({}, CHAT)
    end)

    it("creates nothing in combat, silently", function()
        STATE.combat = true
        ns.CreateIceBlockMacro()
        ns.CreateStopcastMacro(ns.D.STOPCAST_SPELLS[1])
        STATE.combat = false
        assert.are.equal(0, #MACROS)
        assert.are.same({}, CHAT)
    end)

    it("leaves the Polymorph macro's name and text as they were", function()
        ns.CreatePolymorphMacro()
        assert.are.equal("SCB Polymorph", MACROS[1].name)
        assert.are.equal("#showtooltip " .. ns.SpellName(118), lines(MACROS[1].body)[1])
    end)
end)

describe("the Macros tab", function()
    -- Every frame under `frame` matching `test`, depth first.
    local function find(frame, test, found)
        found = found or {}
        for _, child in ipairs(frame.children) do
            if test(child) then found[#found + 1] = child end
            find(child, test, found)
        end
        return found
    end

    it("creates the macro of the spell chosen in its dropdown", function()
        local ns = login(nil)
        _G.MACROS = {}
        ns.ToggleSettings()
        local wanted = ns.D.STOPCAST_SPELLS[3]

        -- The dropdown offering the stopcasting spells: pick the third through its menu
        local picked = false
        for _, dd in ipairs(find(SimpleConjureBarSettings, function(f) return f.kind == "DropdownButton" end)) do
            local radios = {}
            dd.menuFn(dd, { CreateRadio = function(_, text, _, select) radios[#radios + 1] = { text, select } end })
            if #radios == #ns.D.STOPCAST_SPELLS
                and radios[3][1] == ns.LocalName(ns.SpellName(wanted), ns.D.SPELL_NAME_KEYS[wanted]) then
                radios[3][2]()
                picked = true
            end
        end
        assert.is_true(picked)
        assert.are.equal(wanted, SimpleConjureBarDB.macroStopcast)

        -- Three "Create macro" buttons: Polymorph, Ice Block, stopcasting
        local buttons = find(SimpleConjureBarSettings, function(f) return f.text == ns.L.BTN_CREATE_MACRO end)
        assert.are.equal(3, #buttons)
        RUNSCRIPT(buttons[3], "OnClick", "LeftButton", false)
        assert.are.equal("SCB " .. ns.SpellName(wanted), MACROS[1].name)
        RUNSCRIPT(buttons[2], "OnClick", "LeftButton", false)
        assert.are.equal("SCB " .. ns.SpellName(ns.D.SPELL_ICE_BLOCK), MACROS[2].name)
        RUNSCRIPT(buttons[1], "OnClick", "LeftButton", false)
        assert.are.equal("SCB Polymorph", MACROS[3].name)
    end)

    it("heads the Polymorph section with the spell's name, like the others", function()
        local ns = login(nil)
        ns.ToggleSettings()
        local function label(id) return ns.LocalName(ns.SpellName(id), ns.D.SPELL_NAME_KEYS[id]) end
        local texts = {}
        local function collect(frame)
            for _, r in ipairs(frame.regions) do if r.text then texts[r.text] = true end end
            for _, c in ipairs(frame.children) do collect(c) end
        end
        collect(SimpleConjureBarSettings)
        assert.is_true(texts[label(ns.D.SPELL_POLYMORPH)], "Polymorph header")
        assert.is_true(texts[label(ns.D.SPELL_ICE_BLOCK)], "Ice Block header")
        assert.is_nil(rawget(ns.locales.enUS, "BTN_POLY_MACRO"))
    end)
end)

describe("the chosen stopcasting spell", function()
    it("defaults to the first stopcasting spell", function()
        local ns, db = login(nil)
        assert.are.equal(ns.D.STOPCAST_SPELLS[1], db.macroStopcast)
    end)

    it("survives a reload when it is one of the stopcasting spells", function()
        local ns = addon.load("enUS")
        for _, id in ipairs(ns.D.STOPCAST_SPELLS) do
            local _, db = login({ macroStopcast = id })
            assert.are.equal(id, db.macroStopcast)
        end
    end)

    it("falls back to the first for another spell, a string or nothing", function()
        local ns = addon.load("enUS")
        for _, bad in ipairs({ ns.D.SPELL_ICE_BLOCK, 118, "2139", -1, 0 / 0 }) do
            local _, db = login({ macroStopcast = bad })
            assert.are.equal(ns.D.STOPCAST_SPELLS[1], db.macroStopcast, tostring(bad))
        end
    end)
end)
