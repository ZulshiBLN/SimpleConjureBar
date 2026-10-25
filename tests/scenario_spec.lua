-- The smoke scenario of the unpublished build 1.37, ported from the Python/lupa runner: one mocked
-- client, played through in order - login with the old-name import, solo,
-- group, combat, raid, the settings window and chat commands, demo mode, the
-- language switch, merchant, trade, macro and bug report. Each block builds on
-- the state the one before left, so they run in this order and share it.
--
-- The mock cannot prove secure or taint behaviour (rules/testing.md); that is
-- checked in game.

local addon = require("addon")

describe("the addon in a mocked client", function()
    local ns, b, db

    setup(function()
        -- Before login: no settings of our own, the old addon's settings saved.
        _G.SimpleConjureBarDB = nil
        _G.ConjureBarDB = nil
        ns = addon.load("deDE")
        _G.ConjureBarDB = { locked = true, runeColor = { r = 1 } }
        FIRE("PLAYER_LOGIN")
        RUNTIMERS()
        db = SimpleConjureBarDB
        b = ns.buttons
    end)

    it("imports the old addon's settings and migrates them", function()
        assert.is_true(db.locked)
        assert.is_nil(db.runeColor)
        assert.are.equal(ns.D.DB_VERSION, db.dbVersion)
    end)

    it("sets up the buttons for a solo mage", function()
        assert.are.equal("item", b.Water:GetAttribute("type1"))
        assert.are.equal(ns.D.WATER_SPELLS[1], b.Water:GetAttribute("spell2"))
        assert.are.equal("player", b.Intellect:GetAttribute("unit1"))
        assert.are.equal(ns.D.INTELLECT_RANKS[1].id, b.Intellect:GetAttribute("spell1"))
        assert.is_nil(b.Intellect:GetAttribute("type2")) -- solo no right click (ruleset plan 2026-10-23-intellect-range)
        assert.are.equal("/use item:8008\n/use item:8007\n/use item:5513\n/use item:5514",
            b.ManaGem:GetAttribute("macrotext1"))
        assert.are.equal(3, b.Teleport.count:GetText())
        assert.are.equal(1, b.Intellect.count:GetText())
    end)

    it("does not rewrite secure attributes that did not change", function()
        local writes = b.Intellect.attrWrites
        ns.UpdateBuffState()
        assert.are.equal(writes, b.Intellect.attrWrites)
    end)

    it("chooses group targets and keeps a ticker running in a group", function()
        STATE.group = true; STATE.members = 3
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
        -- three in need: Brilliance on the left, on the player
        assert.are.equal(ns.D.SPELL_ARCANE_BRILLIANCE, b.Intellect:GetAttribute("spell1"))
        assert.are.equal("player", b.Intellect:GetAttribute("unit1"))

        AURAS["playerSpell1459"] = true
        FIRE("UNIT_AURA", "player"); RUNTIMERS()
        -- two in need, below the threshold of three: the single buff
        assert.are.equal("party1", b.Intellect:GetAttribute("unit1"))
        assert.are.equal(2, b.Intellect.count:GetText())
        assert.are.equal(1, #TICKERS)
        assert.is_falsy(TICKERS[1].cancelled)
        TICK()
    end)

    it("hides the count in combat and recounts after it", function()
        STATE.combat = true
        FIRE("PLAYER_REGEN_DISABLED")
        assert.is_true(TICKERS[1].cancelled)
        AURAS["party1Spell1459"] = true
        FIRE("UNIT_AURA", "party1"); RUNTIMERS()
        -- no click works in combat (ruleset plan 2026-10-25-combat-locks)
        assert.are.equal("", b.Intellect.count:GetText())
        FIRE("UNIT_AURA", "partypet1"); RUNTIMERS()
        FIRE("PLAYER_TARGET_CHANGED"); RUNTIMERS()
        STATE.combat = false
        FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.are.equal(1, b.Intellect.count:GetText())
    end)

    it("picks a raid target, and stops the ticker solo again", function()
        STATE.raid = true; STATE.members = 12
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
        assert.is_not_nil(b.Intellect:GetAttribute("unit1"))
        STATE.raid = false; STATE.group = false; STATE.members = 0
        FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
        assert.is_true(TICKERS[#TICKERS].cancelled)
        STATE.target = true
        FIRE("PLAYER_TARGET_CHANGED"); RUNTIMERS()
    end)

    it("opens the settings and runs every chat command", function()
        SlashCmdList.SIMPLECONJUREBAR("")
        assert.is_true(SimpleConjureBarSettings:IsShown())
        for _, cmd in ipairs({ "help", "lock", "minimap", "demo" }) do
            SlashCmdList.SIMPLECONJUREBAR(cmd)
        end
        RUNTIMERS()
        for _, key in ipairs({ "Water", "Food", "ManaGem", "Intellect", "Armor", "Teleport" }) do
            RUNSCRIPT(b[key], "OnClick", "LeftButton", false)
            RUNSCRIPT(b[key], "OnClick", "RightButton", false)
        end
        for _, cmd in ipairs({ "demo", "debug", "reset", "xyz" }) do
            SlashCmdList.SIMPLECONJUREBAR(cmd)
        end
    end)

    it("re-renders registered texts on a language switch", function()
        local function findText(frame, wanted)
            for _, r in ipairs(frame.regions) do if r.text == wanted then return true end end
            for _, c in ipairs(frame.children) do
                if c.fs and c.fs.text == wanted then return true end
                if findText(c, wanted) then return true end
            end
            return false
        end
        local window = SimpleConjureBarSettings
        assert.is_true(findText(window, ns.locales.deDE.TAB_GENERAL))
        ns.ApplyLanguage("koKR"); RUNTIMERS()
        assert.is_true(findText(window, ns.locales.koKR.TAB_GENERAL))
        assert.is_true(findText(ns.bar, ns.locales.koKR.DEMO_LABEL))
        ns.ApplyLanguage("enUS"); RUNTIMERS()
        assert.is_true(findText(ns.bar, ns.locales.enUS.DEMO_LABEL))
        assert.is_true(findText(window, ns.locales.enUS.RELOAD_UI))
    end)

    it("buys reagents once, also when the vendor list arrives late", function()
        STATE.merchantItems = 3
        FIRE("MERCHANT_SHOW")
        assert.are.equal(2, #BUYS)

        STATE.merchantItems = 0; _G.BUYS = {}; STATE.now = 200
        FIRE("MERCHANT_SHOW"); STATE.merchantItems = 3; FIRE("MERCHANT_UPDATE"); FIRE("MERCHANT_UPDATE")
        assert.are.equal(2, #BUYS)
    end)

    it("fills the trade window only for the player that was clicked", function()
        -- The best water and food in the bags, as Trade.lua picks them.
        local function best(list)
            for _, id in ipairs(list) do
                if (ITEMS[id] or 0) > 0 then return id end
            end
        end
        STATE.target = true

        -- Someone else opens the trade after the click: nothing goes in.
        _G.TRADE_SLOTS = {}
        RUNSCRIPT(b.Water, "OnClick", "MiddleButton", false)
        STATE.tradeGuid = "Player-1-other"; FIRE("TRADE_SHOW")
        assert.are.same({}, TRADE_SLOTS)

        -- The clicked player, a mana class here, gets water and food.
        RUNSCRIPT(b.Water, "OnClick", "MiddleButton", false)
        STATE.tradeGuid = UnitGUID("target"); FIRE("TRADE_SHOW")
        assert.are.same({ best(ns.D.WATER_ITEMS), best(ns.D.FOOD_ITEMS) }, TRADE_SLOTS)
    end)

    it("keeps the settings closed in combat", function()
        SimpleConjureBarSettings:Hide()
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        SlashCmdList.SIMPLECONJUREBAR("")
        assert.is_false(SimpleConjureBarSettings:IsShown())
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED")
        SimpleConjureBar_OnCompartmentClick("SimpleConjureBar", "LeftButton")
        SimpleConjureBar_OnCompartmentEnter("SimpleConjureBar", UIParent)
    end)

    it("does not buy twice when auto-buy is switched while the list loads", function()
        _G.BUYS = {}; STATE.now = 300
        STATE.merchantItems = 0; FIRE("MERCHANT_SHOW")
        db.autoBuy = false; FIRE("MERCHANT_CLOSED")
        db.autoBuy = true; STATE.merchantItems = 3; FIRE("MERCHANT_SHOW"); FIRE("MERCHANT_UPDATE")
        assert.are.equal(2, #BUYS)
    end)

    it("keeps the buff state from before combat while auras are unreadable", function()
        local armorBefore = b.Armor.antsShown
        STATE.group = false; _G.AURAS = { ["playerSpell1459"] = true }; _G.AURALIST = {}
        ns.UpdateBuffState()
        assert.are.equal("", b.Intellect.count:GetText())
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true; _G.AURAS = {}
        FIRE("UNIT_AURA", "player"); RUNTIMERS(); ns.UpdateBuffState()
        assert.are.equal("", b.Intellect.count:GetText())
        assert.is_true(not b.Armor.antsShown or b.Armor.antsShown == armorBefore)
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        -- solo the line names the case, without a number (ruleset plan 2026-10-23-intellect-range)
        assert.are.equal(ns.L.SELF_MISSING:format(ns.LocalName(ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT")),
            b.Intellect.hint2)
    end)

    it("opens above the Blizzard settings panel", function()
        _G.SettingsPanel = CreateFrame("Frame", "SettingsPanel")
        ns.OpenSettings(true)
        assert.is_true(SimpleConjureBarSettings:IsShown() and SettingsPanel:IsShown())
        SimpleConjureBarSettings:Hide()
    end)

    it("never spends below the gold reserve, and locks after a purchase", function()
        db.goldReserve = 1000; _G.BUYS = {}; STATE.now = 500
        ITEMS[17031] = 0; ITEMS[17020] = 0
        STATE.merchantItems = 3; FIRE("MERCHANT_SHOW")
        assert.are.equal(0, #BUYS)

        db.goldReserve = 1
        FIRE("MERCHANT_SHOW")
        local bought = #BUYS
        FIRE("MERCHANT_CLOSED"); FIRE("MERCHANT_SHOW")
        assert.is_true(bought > 0)
        assert.are.equal(bought, #BUYS)
    end)

    it("counts a weaker Intellect buff as missing and a stronger one as covered", function()
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        _G.AURAS = {}; _G.AURALIST = { player = { 12176 } }
        ns.UpdateBuffState()
        assert.are.equal(1, b.Intellect.count:GetText())
        _G.AURALIST = { player = { 999, 10157 } }
        ns.UpdateBuffState()
        assert.are.equal("", b.Intellect.count:GetText())
        SlashCmdList.SIMPLECONJUREBAR("debug")
    end)

    it("creates the Polymorph macro once, per character, with the chosen marker", function()
        _G.MACROS = { { name = "SCB Polymorph", body = "old" } }
        ns.CreatePolymorphMacro(); ns.CreatePolymorphMacro()
        assert.are.equal(1, #MACROS)
        assert.are.equal("SCB Polymorph", MACROS[1].name)
        assert.is_true(MACROS[1].perChar)
        assert.is_truthy(MACROS[1].body:find("Spell118"))
        assert.is_true(#MACROS[1].body <= 255)

        db.macroMarker = 8
        ns.CreatePolymorphMacro()
        assert.is_truthy(MACROS[1].body:find("/tm %[@focus,harm,nodead%] 8"))

        -- Blizzard's macro window switches to its first tab (general) when shown; the
        -- addon must switch it to the second (character) afterwards, and stay open.
        local tabs = {}
        _G.MacroFrame = { ChangeTab = function(_, id) tabs[#tabs + 1] = id end }
        _G.ShowMacroFrame = function() _G.SHOWN_MACRO = true; MacroFrame:ChangeTab(1) end
        SimpleConjureBarSettings:Show(); ns.ShowMacroWindow()
        assert.is_true(SHOWN_MACRO)
        assert.are.same({ 1, 2 }, tabs)
        assert.is_true(SimpleConjureBarSettings:IsShown())
    end)

    it("builds a bug report with this addon's errors and no personal data", function()
        SlashCmdList.SIMPLECONJUREBAR("bug")
        local r = SimpleConjureBarReport
        assert.is_true(r and r:IsShown())
        -- the box holds the report as a code (ruleset plan 2026-10-21-bug-report-code)
        local text = ns.ReportCode.Decode(r.report:GetText() or "") or ""
        assert.is_truthy(text:find("Addon version: " .. ns.VERSION, 1, true))
        assert.is_truthy(text:find("Bar.lua:10", 1, true))
        assert.is_falsy(text:find("OtherAddon", 1, true))
        assert.is_truthy(text:find("x3", 1, true))
        assert.is_falsy(text:find("Name_player", 1, true))

        r.desc:SetText("Bar vanished"); RUNSCRIPT(r.desc, "OnTextChanged", true)
        assert.is_truthy((ns.ReportCode.Decode(r.report:GetText() or "") or ""):find("Bar vanished", 1, true))

        -- Where to send it: the repository's issues, shown and selectable
        assert.is_truthy(ns.D.BUG_REPORT_URL:find("^https://github%.com/ZulshiBLN/SimpleConjureBar/issues"))
        local shownUrl, step3
        for _, c in ipairs(r.children) do
            if c.kind == "EditBox" and c.text == ns.D.BUG_REPORT_URL then shownUrl = c end
        end
        for _, region in ipairs(r.regions) do
            if region.text == ns.L.REPORT_STEP3 then step3 = region end
        end
        assert.is_truthy(shownUrl and shownUrl:IsShown(), "the URL box")
        assert.is_truthy(step3, "the step telling where to paste it")
    end)

    it("raised no Lua error in any script, hook or timer along the way", function()
        assert.are.same({}, STATE.errors)
    end)
end)
