-- The mock records what the addon sets; a spec reading a field the mock never fills would
-- pass on nil. These pin the parts specs rely on.

describe("the mock", function()
    before_each(function() assert(loadfile("tests/helpers/mock.lua"))() end)

    it("records an animation group's looping, play state and flipbook", function()
        local tex = CreateFrame("Frame"):CreateTexture()
        local group = tex:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local flip = group:CreateAnimation("FlipBook")
        flip:SetFlipBookRows(6); flip:SetFlipBookColumns(5); flip:SetFlipBookFrames(30)
        flip:SetDuration(1.5)
        assert.are.same({ "REPEAT", "FlipBook", 6, 5, 30, 1.5 },
            { group.looping, flip.kind, flip.rows, flip.columns, flip.frames, flip:GetDuration() })
        assert.is_false(group:IsPlaying())
        group:Play(); assert.is_true(group:IsPlaying())
        group:Stop(); assert.is_false(group:IsPlaying())
    end)

    it("runs a wrapped snippet's bodies and the secure auto-hide", function()
        local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
        local holder = CreateFrame("Frame", nil, UIParent)
        local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
        assert.is_true(holder.protected) -- it holds a secure button
        header:SetFrameRef("fly", holder)
        b:SetAttribute("type1", "spell"); b:SetAttribute("spell1", 7)
        header:WrapScript(b, "OnClick", [[
            local fly = owner:GetFrameRef("fly")
            fly:RegisterAutoHide(3); fly:AddToAutoHide(self)
            return nil, "go"
        ]], [[ self:SetAttribute("seen", message) ]])
        RUNCLICK(b, "LeftButton", false)
        assert.are.same({ 3, b }, { holder.autoHide, holder.autoHideWith[1] })
        assert.are.equal("go", b:GetAttribute("seen"))
        assert.are.same({ { spell = 7 } }, STATE.casts)

        header:WrapScript(b, "OnClick", [[ if PlayerInCombat() then return false end ]])
        STATE.combat = true
        RUNCLICK(b, "LeftButton", false)
        assert.are.equal(1, #STATE.casts)
        assert.are.same({}, STATE.errors)
    end)

    it("runs PreClick first, and a macro's nested click and targeting", function()
        local order = {}
        local inner = CreateFrame("Button", "MockInner", UIParent, "SecureActionButtonTemplate")
        inner:SetAttribute("type", "spell"); inner:SetAttribute("unit", "target")
        local outer = CreateFrame("Button", "MockOuter", UIParent, "SecureActionButtonTemplate")
        outer:SetAttribute("type3", "macro")
        outer:SetAttribute("macrotext3", "/click MockInner LeftButton 1\n/targetfriendplayer")
        outer:SetScript("PreClick", function() order[#order + 1] = "pre"; inner:SetAttribute("spell", 9) end)
        outer:SetScript("OnClick", function() order[#order + 1] = "click" end)
        STATE.friends = { { class = "PRIEST" }, { class = "WARRIOR" } }
        -- The nested "/click ... 1" casts whether actions fire on key down or up
        for _, keyDown in ipairs({ false, true }) do
            STATE.keyDown, STATE.casts = keyDown, {}
            RUNCLICK(outer, "MiddleButton", keyDown)
            assert.are.same({ { spell = 9, unit = "target" } }, STATE.casts)
        end
        assert.are.same({ "pre", "click", "pre", "click" }, order)
        assert.are.equal(2, STATE.targetedNext)
        assert.are.equal("WARRIOR", STATE.units.target.class) -- the second friend
        RUNCLICK(outer, "MiddleButton", true)
        assert.is_nil(STATE.units.target) -- no friendly player left
        assert.are.same({}, STATE.errors)
    end)

    it("describes units on request and answers the defaults otherwise", function()
        STATE.units.party1 = { class = "WARRIOR", level = -1, player = false, assist = false,
                               pvp = true, dead = true, connected = false, range = false,
                               name = "Bob", auras = { 1459 } }
        assert.are.same({ "WARRIOR", -1, false, false, true, true, false, false, "Bob" }, {
            select(2, UnitClass("party1")), UnitLevel("party1"), UnitIsPlayer("party1"),
            UnitCanAssist("player", "party1"), UnitIsPVP("party1"), UnitIsDeadOrGhost("party1"),
            UnitIsConnected("party1"), C_Spell.IsSpellInRange(1459, "party1"), UnitName("party1") })
        assert.is_not_nil(C_UnitAuras.GetAuraDataBySpellName("party1", "Spell1459"))
        assert.are.equal(1459, C_UnitAuras.GetAuraDataByIndex("party1", 1).spellId)
        assert.are.same({ "MAGE", 60, true, true, false, false, true, true }, {
            select(2, UnitClass("party2")), UnitLevel("party2"), UnitIsPlayer("party2"),
            UnitCanAssist("player", "party2"), UnitIsPVP("party2"), UnitIsDeadOrGhost("party2"),
            UnitIsConnected("party2"), C_Spell.IsSpellInRange(1459, "party2") })
        STATE.cooldowns[1459] = 100
        assert.are.equal(100, C_Spell.GetSpellCooldown(1459).startTime)
        assert.are.equal(0, C_Spell.GetSpellCooldown(1460).startTime)
        assert.is_false(C_Secrets.ShouldAurasBeSecret())
        STATE.secret = true
        assert.is_true(C_Secrets.ShouldAurasBeSecret())
    end)

    it("keeps a clock, aura expiry and cancellable timers apart from RUNTIMERS", function()
        assert.are.equal(100, GetTime())
        STATE.units.party1 = { auras = { 1459, { id = 1460, expires = 400 } } }
        AURAS["party1Spell99"] = true
        assert.are.equal(0, C_UnitAuras.GetAuraDataBySpellName("party1", "Spell1459").expirationTime)
        local named = C_UnitAuras.GetAuraDataBySpellName("party1", "Spell1460")
        assert.are.same({ 1460, 400 }, { named.spellId, named.expirationTime })
        assert.are.equal(0, C_UnitAuras.GetAuraDataBySpellName("party1", "Spell99").expirationTime)
        local indexed = C_UnitAuras.GetAuraDataByIndex("party1", 2)
        assert.are.same({ 1460, 400 }, { indexed.spellId, indexed.expirationTime })
        -- a higher rank answers to the spell's one name
        STATE.units.party2 = { auras = { { id = 10157, as = 1459 } } }
        assert.are.equal(10157, C_UnitAuras.GetAuraDataBySpellName("party2", "Spell1459").spellId)

        local fired = {}
        local early = C_Timer.NewTimer(50, function() fired[#fired + 1] = "early" end)
        local late = C_Timer.NewTimer(200, function() fired[#fired + 1] = "late" end)
        local gone = C_Timer.NewTimer(10, function() fired[#fired + 1] = "gone" end)
        gone:Cancel()
        assert.is_true(gone:IsCancelled())
        assert.are.equal(50, early.delay)
        RUNTIMERS()
        assert.are.same({}, fired)
        ADVANCE(49)
        assert.are.same({}, fired)
        ADVANCE(1)
        assert.are.same({ "early" }, fired)
        assert.are.equal(150, GetTime())
        ADVANCE(150)
        assert.are.same({ "early", "late" }, fired)
        assert.is_false(late:IsCancelled())
    end)

    it("shows a dropdown's selected text as of its last generation", function()
        local dd = CreateFrame("DropdownButton", nil, nil, "WowStyle1DropdownTemplate")
        local label, chosen = "one", "a"
        dd:SetupMenu(function(_, root)
            root:CreateRadio(label, function() return chosen == "a" end)
            root:CreateRadio("two", function() return chosen == "b" end)
        end)
        assert.are.equal("one", dd.selectedText)
        label = "eins"
        assert.are.equal("one", dd.selectedText) -- not before the menu is generated again
        dd:GenerateMenu()
        assert.are.equal("eins", dd.selectedText)
    end)

    it("records an edit box's selection and focus", function()
        local box = CreateFrame("EditBox")
        local gained = 0
        box:SetScript("OnEditFocusGained", function() gained = gained + 1 end)
        box:SetFocus()
        assert.are.same({ true, 1 }, { box.focused, gained })
        box:HighlightText()
        assert.are.equal("all", box.selection)
        box:HighlightText(0, 0)
        assert.are.equal("none", box.selection)
        box:ClearFocus()
        assert.is_false(box.focused)
    end)

    it("records a texture's atlas, colour and anchors", function()
        local tex = CreateFrame("Frame"):CreateTexture()
        tex:SetAtlas("x"); tex:SetVertexColor(1, 0.5, 0, 1)
        tex:SetPoint("TOP", UIParent, "BOTTOM", 0, 6)
        assert.are.equal("x", tex.atlas)
        assert.are.same({ 1, 0.5, 0, 1 }, tex.vertexColor)
        assert.are.same({ "TOP", UIParent, "BOTTOM", 0, 6 }, { tex:GetPoint() })
        tex:ClearAllPoints()
        assert.is_nil(tex:GetPoint())
    end)
end)
