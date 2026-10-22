-- The globals rule is only enforced if .luacheckrc is actually strict. This
-- runs the real luacheck with the real config against snippets that must be
-- refused, so a config loosened by accident turns this red.

local luacheck = require("luacheck")
local lfs = require("lfs")

-- The config is Lua that assigns globals; run it in an empty environment and
-- hand what it set to luacheck as options. The per-path `files` section is
-- returned apart: a snippet stands in for ordinary addon code unless a test
-- names the path it stands for.
local function loadConfig()
    local options = { files = {} }
    local chunk = assert(loadfile(".luacheckrc"))
    setfenv(chunk, options)
    chunk()
    local files = options.files
    options.files = nil
    return options, files
end

-- Options for sources at `paths`: the config, plus each path's own section in
-- the array part, which luacheck applies per source.
local function configFor(paths)
    local options, files = loadConfig()
    for i, path in ipairs(paths) do options[i] = files[path] or {} end
    return options
end

local function warningsFor(source)
    local report = luacheck.check_strings({ source }, loadConfig())
    return report.warnings + report.errors
end

-- Any warning is not enough: a loosened config can trade the refusal for a
-- different, weaker warning. Each case asks for the refusal's own code.
local function hasCode(source, code, path)
    local options = path and configFor({ path }) or loadConfig()
    local report = luacheck.check_strings({ source }, options)
    for _, w in ipairs(report[1]) do
        if w.code == code then return true end
    end
    return false
end

describe(".luacheckrc", function()
    it("refuses writing a global the rule does not allow", function()
        assert.is_true(hasCode("SimpleConjureBarScratch = 1\n", "111"))
    end)

    it("refuses io, os, require, dofile and loadfile", function()
        for _, name in ipairs({ "io", "os", "require", "dofile", "loadfile" }) do
            assert.is_true(hasCode("local x = " .. name .. "\nreturn x\n", "113"), name)
        end
    end)

    it("refuses defining a top-level function", function()
        assert.is_true(hasCode("function SimpleConjureBarHelper() end\n", "111"))
    end)

    it("refuses writing another addon's slash command entry", function()
        assert.is_true(hasCode("SlashCmdList.SOMEONE_ELSE = print\n", "142"))
    end)

    it("refuses a color picker field the old API branch does not set", function()
        assert.is_true(hasCode("ColorPickerFrame.somethingElse = 1\n", "142"))
    end)

    -- The two names once excepted are reported again (code review 1.1.0, F-10)
    it("reports an unused local in every addon file, with no exception left", function()
        assert.is_true(hasCode("local GAP = 1\n", "211", "SimpleConjureBar/Bar.lua"))
        assert.is_true(hasCode("local L = 1\n", "211", "SimpleConjureBar/Report.lua"))
        assert.is_true(hasCode("local GAP = 1\n", "211", "SimpleConjureBar/Core.lua"))
    end)

    it("allows exactly the globals the rule names", function()
        local allowed = table.concat({
            "SimpleConjureBarDB = {}",
            "SimpleConjureBarGlobalDB = {}",
            "ConjureBarDB = nil",
            'SLASH_SIMPLECONJUREBAR1 = "/scb"',
            'SLASH_SIMPLECONJUREBAR2 = "/cbar"',
            "SlashCmdList.SIMPLECONJUREBAR = print",
            "function SimpleConjureBar_OnCompartmentClick() end",
            "function SimpleConjureBar_OnCompartmentEnter() end",
            "function SimpleConjureBar_OnCompartmentLeave() end",
            'BINDING_HEADER_SIMPLECONJUREBAR = "x"',
        }, "\n") .. "\n"
        assert.are.equal(0, warningsFor(allowed))
    end)

    it("finds the addon's own files clean", function()
        local sources, names = {}, {}
        for entry in lfs.dir("SimpleConjureBar") do
            if entry:match("%.lua$") then
                local path = "SimpleConjureBar/" .. entry
                local f = assert(io.open(path, "rb"))
                sources[#sources + 1] = f:read("*a")
                names[#names + 1] = path
                f:close()
            end
        end
        assert.is_true(#sources > 0)
        local report = luacheck.check_strings(sources, configFor(names))
        assert.are.equal(0, report.warnings + report.errors, table.concat(names, ", "))
    end)
end)
