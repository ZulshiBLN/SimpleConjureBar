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
