-- rules/localization.md: every enUS key exists in every other locale, with
-- the placeholders in the same order. The keys, the locale list and the
-- esMX -> esES inheritance are read from Locales.lua, never retyped here.

local addon = require("addon")

-- Runs Locales.lua as the client would, with GetLocale answering `client`,
-- and returns the namespace it fills. A changed source can be passed in.
local function load(client, source)
    local ns = {}
    local chunk = assert(loadstring(source or addon.read("SimpleConjureBar/Locales.lua"), "Locales.lua"))
    setfenv(chunk, setmetatable({ GetLocale = function() return client end }, { __index = _G }))
    chunk("SimpleConjureBar", ns)
    return ns
end

-- The placeholder letters in order, e.g. "sd" for "Missing %s: %d".
local function placeholders(s)
    local seq = {}
    for p in s:gmatch("%%([sd])") do seq[#seq + 1] = p end
    return table.concat(seq)
end

-- The text a locale table gives for a key: its own, or what it inherits.
local function lookup(t, key)
    local v = rawget(t, key)
    if v ~= nil then return v end
    local mt = getmetatable(t)
    local parent = mt and type(mt.__index) == "table" and mt.__index
    return parent and lookup(parent, key)
end

describe("locales", function()
    local ns = load("enUS")

    it("lists every locale it defines, and enUS defines keys", function()
        assert.is_true(#ns.LOCALE_ORDER > 1)
        assert.is_not_nil(next(ns.locales.enUS))
        for _, code in ipairs(ns.LOCALE_ORDER) do
            assert.is_table(ns.locales[code], code)
        end
    end)

    it("has every enUS key in every locale", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            for key in pairs(ns.locales.enUS) do
                assert.is_string(lookup(ns.locales[code], key), code .. "." .. key)
            end
        end
    end)

    it("keeps each text's placeholders in the order of enUS", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            for key, english in pairs(ns.locales.enUS) do
                local text = lookup(ns.locales[code], key)
                assert.are.equal(placeholders(english), placeholders(text), code .. "." .. key)
            end
        end
    end)

    it("defines no key that enUS lacks", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            for key in pairs(ns.locales[code]) do
                assert.is_string(ns.locales.enUS[key], code .. "." .. key)
            end
        end
    end)

    it("lets esMX inherit what it does not override from esES", function()
        local esMX, esES = ns.locales.esMX, ns.locales.esES
        local inherited = 0
        for key in pairs(ns.locales.enUS) do
            if rawget(esMX, key) == nil then
                inherited = inherited + 1
                assert.are.equal(esES[key], lookup(esMX, key), key)
            end
        end
        assert.is_true(inherited > 0)
    end)

    -- The check above must be able to fail: drop one German entry from a copy
    -- of the source and it has to notice.
    it("would notice a key missing from a locale", function()
        local source = addon.read("SimpleConjureBar/Locales.lua")
        local cut, n = source:gsub("(locales%.deDE = {.-)\n%s*DRAG = [^\n]*", "%1", 1)
        assert.are.equal(1, n, "the test copy should lose deDE.DRAG")
        local broken = load("deDE", cut)
        assert.is_nil(lookup(broken.locales.deDE, "DRAG"))
        assert.are.equal(broken.locales.enUS.DRAG, broken.L.DRAG) -- English at runtime
    end)

    it("falls back to English at runtime for the client's language", function()
        local de = load("deDE")
        assert.are.equal("deDE", de.GetLocaleCode())
        assert.are.equal(de.locales.deDE.TAB_GENERAL, de.L.TAB_GENERAL)
        assert.are.equal("NO_SUCH_KEY", de.L.NO_SUCH_KEY)
        local en = load("enGB")
        assert.are.equal("enUS", en.GetLocaleCode())
    end)
end)
