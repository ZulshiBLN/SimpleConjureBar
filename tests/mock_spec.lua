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
