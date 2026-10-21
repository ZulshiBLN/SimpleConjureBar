-- The bug report: everything needed to find and fix a bug without asking the player back, and
-- nothing about the player (ruleset plan 2026-10-17-bug-report-details).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

local function contains(lines, pattern)
    for _, l in ipairs(lines) do if l:find(pattern) then return l end end
end

describe("the state snapshot", function()
    it("lists every button with its click, the hidden buttons and a flyout child", function()
        local ns = login()
        ns.Rebuild(); RUNTIMERS()
        local lines = ns.StateSnapshot()
        for _, key in ipairs(ns.D.DEFAULT_ORDER) do
            assert.is_truthy(contains(lines, "^button " .. key .. " "), key)
        end
        local intel = contains(lines, "^button Intellect ")
        assert.is_truthy(intel:find("type1=spell", 1, true), intel)
        assert.is_truthy(intel:find("unit1=player", 1, true), intel)
        assert.is_truthy(contains(lines, "^button SimpleConjureBarBuffAll "))
        assert.is_truthy(contains(lines, "^button SimpleConjureBarBuffRun "))
        assert.is_truthy(contains(lines, "^button SimpleConjureBar_ArmorFlyout1 "))
        assert.is_truthy(contains(lines, "^keydown "))
        assert.is_truthy(contains(lines, "^combat no$"))
    end)

    it("counts the addon's items by ID, the group by class and own buffs with minutes left", function()
        local ns = login()
        local D = ns.D
        STATE.units.player = { auras = { { id = D.ARMOR_BUFF_IDS[1], expires = GetTime() + 600 }, 8098 } }
        STATE.units.party1 = { class = "PRIEST" }
        STATE.group, STATE.members = true, 2
        local lines = ns.StateSnapshot()
        assert.is_truthy(contains(lines, "^bags .*" .. D.ITEM_RUNE_TELE .. "=3"))
        assert.is_truthy(contains(lines, "^group party size=2 .*PRIEST=1"))
        local buffs = contains(lines, "^buffs ")
        assert.is_truthy(buffs:find(D.ARMOR_BUFF_IDS[1] .. ":10m", 1, true), buffs)
        assert.is_truthy(buffs:find("8098:-", 1, true), buffs)
    end)

    it("is what /scb debug prints", function()
        local ns = login()
        _G.CHAT = {}
        SlashCmdList.SIMPLECONJUREBAR("debug")
        local printed = table.concat(CHAT, "\n")
        for _, l in ipairs(ns.StateSnapshot()) do
            assert.is_truthy(printed:find(l, 1, true), l)
        end
    end)
end)

describe("the loaded addons", function()
    it("are listed by folder name and version, at most 60", function()
        local ns = login()
        _G.ADDONS = {}
        for i = 1, 65 do ADDONS[i] = { name = "Addon" .. i, title = "|cffff0000Addon " .. i .. "|r", loaded = i ~= 3 } end
        local lines = ns.AddonList()
        assert.are.equal(61, #lines) -- 60 and the count of the rest
        assert.are.equal("Addon1 1.0.0", lines[1])
        assert.is_nil(contains(lines, "^Addon3 "))
        assert.is_truthy(lines[61]:find("4 more", 1, true))
    end)
end)
