-- The bug report as one code, and the decoder that reads it back (ruleset plan
-- 2026-10-21-bug-report-code).

local addon = require("addon")

local function codec()
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns.ReportCode, ns
end

describe("the report code", function()
    it("gives every report back byte for byte, whatever its language", function()
        local RC = codec()
        for _, text in ipairs({ "", "a", "ab", "abc", "## SimpleConjureBar bug report\nmsg x",
            "Rüstung, Größe, ß", "Чародейский интеллект", "奥术智慧，秘法智慧", ("ü"):rep(1000) }) do
            local code = RC.Encode(text)
            assert.is_truthy(code:find("^SCB1:[%w%+/=]*:%x%x%x%x%x%x%x%x$"), code)
            assert.are.equal(text, (RC.Decode(code)))
        end
    end)

    it("reads a code with spaces and line breaks in it, and refuses a damaged or unknown one", function()
        local RC = codec()
        local code = RC.Encode("Portal does nothing")
        local broken = code:sub(1, 10) .. "\n  " .. code:sub(11, 20) .. " \r\n" .. code:sub(21)
        assert.are.equal("Portal does nothing", (RC.Decode(broken)))
        local changed = code:sub(1, 8) .. (code:sub(9, 9) == "A" and "B" or "A") .. code:sub(10)
        assert.is_nil(RC.Decode(changed))
        local report, why = RC.Decode(code:gsub("^SCB1", "SCB2"))
        assert.is_nil(report)
        assert.is_truthy(why:find("unknown code version SCB2", 1, true))
    end)

    it("keeps a report at the cap, all non-ASCII, under GitHub's limit with the form around it", function()
        local RC, ns = codec()
        local text = ns.CapReport(("ä"):rep(20000))
        assert.is_true(#text <= ns.D.REPORT_MAX_BYTES)
        local issue = "### Report code\n\n" .. RC.Encode(text) .. "\n\n### Screenshots\n\n_No response_\n"
        assert.is_true(#issue < 65536, #issue)
    end)
end)

describe("the decoder", function()
    local decoder = dofile("tools/decode-report.lua")
    local function run(input)
        local lines = {}
        local code = decoder.main({ "x" }, function() return input end, function(s) lines[#lines + 1] = s end)
        return code, table.concat(lines, "\n")
    end

    it("prints the report from a whole issue body with the code inside", function()
        local RC = codec()
        local body = "### Report code\n\n```text\n" .. RC.Encode("## SimpleConjureBar bug report\nline two")
            .. "\n```\n\n### Screenshots\n"
        local code, out = run(body)
        assert.are.equal(0, code)
        assert.are.equal("## SimpleConjureBar bug report\nline two", out)
    end)

    it("refuses damaged, oversized and foreign input with one error line and runs nothing", function()
        local RC = codec()
        local good = RC.Encode("report")
        for name, input in pairs({
            damaged = good:sub(1, -3) .. "00",
            oversized = good .. (" "):rep(100001), -- a valid code, made too long
            foreign = good:sub(1, 8) .. "!" .. good:sub(9),
            none = "no code here",
        }) do
            local code, out = run(input)
            assert.are.equal(1, code, name)
            assert.is_truthy(out:find("^error: "), name .. ": " .. out)
            assert.is_nil(out:find("\n"), name)
        end
        _G.RAN = nil -- the code below would set it, were it run
        local code, out = run(RC.Encode('RAN = true; os.exit(9)'))
        assert.are.equal(0, code)
        assert.is_nil(rawget(_G, "RAN"))
        assert.are.equal("RAN = true; os.exit(9)", out)
    end)

    it("shows control characters, invalid UTF-8 and direction overrides as code points", function()
        local RC = codec()
        local text = "a\27[31mb" .. "\127" .. "\194\155" .. "\255" .. "\226\128\174" .. "\226\129\167" .. "ok\tü\n"
        local code, out = run(RC.Encode(text))
        assert.are.equal(0, code)
        assert.are.equal("a<U+001B>[31mb<U+007F><U+009B><U+00FF><U+202E><U+2067>ok\tü\n", out)
    end)

    it("runs as a script with the interpreter that runs busted", function()
        local RC = codec()
        local i = -1
        while arg[i - 1] do i = i - 1 end
        local interpreter = arg[i]
        local path = os.tmpname()
        local f = assert(io.open(path, "wb")); f:write("issue text " .. RC.Encode("from a file") .. " end"); f:close()
        local command = ('"%s" tools/decode-report.lua "%s"'):format(interpreter, path)
        -- cmd.exe drops the outer quotes of a command that starts with one
        if package.config:sub(1, 1) == "\\" then command = '"' .. command .. '"' end
        local p = assert(io.popen(command))
        local out = p:read("*a"); p:close()
        os.remove(path)
        assert.are.equal("from a file\n", out)
    end)
end)
