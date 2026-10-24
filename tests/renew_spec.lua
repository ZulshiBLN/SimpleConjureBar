-- Intellect and armor are renewed shortly before they run out, and a click with nothing to do
-- casts nothing (ruleset plan 2026-10-21-buff-renew).

local addon = require("addon")

local function login(saved)
    _G.SimpleConjureBarDB = saved
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SimpleConjureBarDB
end

-- An Arcane Intellect of this rank with `minutes` left, answering to the spell's name
local function intellect(D, minutes, rank)
    return { id = rank or D.INTELLECT_RANKS[1].id, as = D.SPELL_ARCANE_INTELLECT, expires = GetTime() + minutes * 60 }
end

local function regroup(ns, group, raid, members)
    STATE.group, STATE.raid, STATE.members = group, raid, members
    FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
    ns.UpdateBuffState()
end

local function tooltipLines(ns)
    local lines = {}
    GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    ns.ShowTooltip(ns.buttons.Intellect)
    return lines
end

local function has(lines, wanted)
    for _, l in ipairs(lines) do if l == wanted then return true end end
    return false
end

describe("Arcane Intellect", function()
    it("solo casts nothing while it holds, and renews it within the renew time", function()
        local ns = login()
        local D, L, b = ns.D, ns.L, ns.buttons.Intellect
        STATE.units.player = { auras = { intellect(D, 10) } }
        ns.UpdateBuffState()
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_nil(b:GetAttribute("type2"))
        assert.is_false(b.antsShown)
        local lines = tooltipLines(ns)
        local nothing = L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1")) .. " > " .. L.EVERYONE_BUFFED)
        assert.is_true(has(lines, nothing), table.concat(lines, " | "))
        assert.is_nil(b.hint or b.hintKey) -- solo no right click (ruleset plan 2026-10-23-intellect-range)

        STATE.units.player = { auras = { intellect(D, 4) } }
        ns.UpdateBuffState()
        assert.are.same({ "spell", "player" }, { b:GetAttribute("type1"), b:GetAttribute("unit1") })
        assert.is_true(b.antsShown)
        assert.are.equal("1", tostring(b.count:GetText()))

        SimpleConjureBarDB.intellectRenewMinutes = 0
        ns.UpdateBuffState()
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_false(b.antsShown)
    end)

    it("never renews a buff without expiry or one stronger than ours", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        STATE.units.player = { auras = { D.SPELL_ARCANE_INTELLECT } }
        ns.UpdateBuffState()
        assert.is_nil(b:GetAttribute("type1"))
        -- A level 10 priest takes rank 1 from us; another mage's top rank on him, 1 minute left,
        -- would refuse ours
        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST", level = 10, auras = { intellect(D, 1, D.INTELLECT_RANKS[1].id) } }
        regroup(ns, true, false, 2)
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_nil(b:GetAttribute("type2"))
    end)

    -- ruleset plan 2026-10-23-intellect-range: a lower rank than ours is needed, after the
    -- missing ones (Michel learned a higher rank and nothing glowed)
    it("counts a weaker rank with time left, after the missing", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        local lowest = D.INTELLECT_RANKS[#D.INTELLECT_RANKS].id
        STATE.units.player = { auras = { intellect(D, 30, lowest) } }
        ns.UpdateBuffState()
        assert.are.same({ "spell", "player" }, { b:GetAttribute("type1"), b:GetAttribute("unit1") })
        assert.is_true(b.antsShown)
        assert.are.equal("1", tostring(b.count:GetText()))

        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST", auras = { intellect(D, 30, lowest) } }
        STATE.units.party2 = { class = "PRIEST" }
        regroup(ns, true, false, 3)
        assert.are.equal("2", tostring(b.count:GetText()))
        assert.are.equal("party2", b:GetAttribute("unit1")) -- the missing one first
        STATE.units.party2 = { class = "PRIEST", auras = { intellect(D, 30) } }
        ns.UpdateBuffState()
        assert.are.equal("party1", b:GetAttribute("unit1"))
    end)

    it("does not count our rank with time left, a buff without expiry or an unknown one", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        local unknown = { id = 999999, as = D.SPELL_ARCANE_INTELLECT, expires = GetTime() + 1800 }
        for name, aura in pairs({
            ours = intellect(D, 30),
            ["no expiry"] = D.INTELLECT_RANKS[#D.INTELLECT_RANKS].id,
            unknown = unknown,
        }) do
            STATE.units.player = { auras = { aura } }
            ns.UpdateBuffState()
            assert.is_false(b.antsShown, name)
        end
    end)

    it("in a party buffs a missing member before an expiring one", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST", auras = { intellect(D, 1) } }
        STATE.units.party2 = { class = "PRIEST" }
        regroup(ns, true, false, 3)
        assert.are.equal("party2", b:GetAttribute("unit1")) -- two in need: the single buff on the left
        assert.are.equal("2", tostring(b.count:GetText()))
    end)

    -- code review 1.1.0, F-08
    it("in a party passes a dead and an offline member", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST", dead = true }
        STATE.units.party2 = { class = "DRUID", connected = false }
        STATE.units.party3 = { class = "PALADIN" }
        regroup(ns, true, false, 4)
        assert.are.equal("party3", b:GetAttribute("unit1"))
        assert.are.equal("1", tostring(b.count:GetText()))
    end)

    -- code review 1.1.0, F-14: the scan asked the spell book for every member's rank
    it("asks the spell book once per rank in a scan of a full raid", function()
        local calls = {}
        _G.SimpleConjureBarDB = nil
        local ns = addon.load("enUS", function()
            local known = C_SpellBook.IsSpellKnown
            C_SpellBook.IsSpellKnown = function(id) calls[#calls + 1] = id return known(id) end
        end)
        FIRE("PLAYER_LOGIN"); RUNTIMERS()
        for i = 1, 40 do STATE.units["raid" .. i] = { class = "PRIEST" } end
        regroup(ns, true, true, 40)
        for k in pairs(calls) do calls[k] = nil end
        ns.UpdateBuffState()
        assert.are.equal("40", tostring(ns.buttons.Intellect.count:GetText()))
        local ranks, asked = {}, 0
        for _, r in ipairs(ns.D.INTELLECT_RANKS) do ranks[r.id] = true end
        for _, id in ipairs(calls) do if ranks[id] then asked = asked + 1 end end
        assert.is_true(asked <= #ns.D.INTELLECT_RANKS, asked .. " spell book calls")
    end)

    it("in a raid casts no Brilliance when no subgroup in need is in range", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        for i = 1, 5 do STATE.units["raid" .. i] = { auras = { intellect(D, 30) } } end
        STATE.units.raid6 = { class = "PRIEST", range = false } -- subgroup 2
        regroup(ns, true, true, 6)
        -- nobody in need in range: the single rank, no unit, no cast
        assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_nil(b:GetAttribute("unit1"))
        -- the tooltip says they are out of range, not that it is active (code review 1.1.0, F-04)
        local L = ns.L
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1")) .. " > " .. L.NONE_IN_RANGE)),
            table.concat(lines, " | "))
        assert.are_not.equal(L.EVERYONE_BUFFED, L.NONE_IN_RANGE)
        assert.are.same({}, STATE.errors)
    end)

    it("does not hide a missing armor from Cast next buff when its glowing click has nothing to do", function()
        local ns, db = login()
        local D = ns.D
        db.order = { "Intellect", "Armor", "ManaGem", "Water", "Food", "Teleport", "Portal" }
        for i = 1, 5 do STATE.units["raid" .. i] = { auras = { intellect(D, 30) } } end
        STATE.units.raid6 = { class = "PRIEST", range = false }
        regroup(ns, true, true, 6)
        -- the member out of range makes no glow now (ruleset plan 2026-10-23-intellect-range)
        assert.is_false(ns.buttons.Intellect.antsShown)
        assert.is_true(ns.buttons.Armor.antsShown)
        assert.are.equal("Armor", ns.buffKey:GetAttribute("scbsource"))
    end)

    it("is renewed by Buff & Run when expiring, and passed with time left", function()
        local ns = login()
        local D = ns.D
        STATE.units.target = { class = "PRIEST", auras = { intellect(D, 1, D.INTELLECT_RANKS[1].id) } }
        assert.are.equal(D.INTELLECT_RANKS[1].id, ns.BuffRunSpell("target"))
        STATE.units.target = { class = "PRIEST", auras = { intellect(D, 50, D.INTELLECT_RANKS[1].id) } }
        assert.is_nil(ns.BuffRunSpell("target"))
    end)
end)

-- The timers still waiting
local function pending()
    local list = {}
    for _, t in ipairs(DELAYED) do if not t.cancelled then list[#list + 1] = t end end
    return list
end

-- An armor with `minutes` left
local function armorAura(D, minutes)
    return { id = D.ARMOR_BUFF_IDS[1], expires = GetTime() + minutes * 60 }
end

describe("the armor", function()
    it("glows within its renew time and the buff key holds it, not before", function()
        local ns = login()
        local D = ns.D
        STATE.units.player = { auras = { armorAura(D, 2), intellect(D, 30) } }
        ns.UpdateBuffState()
        assert.is_true(ns.buttons.Armor.antsShown)
        assert.are.equal("Armor", ns.buffKey:GetAttribute("scbsource"))
        STATE.units.player = { auras = { armorAura(D, 10), intellect(D, 30) } }
        ns.UpdateBuffState()
        assert.is_false(ns.buttons.Armor.antsShown)
        assert.is_nil(ns.buffKey:GetAttribute("scbsource"))
    end)
end)

describe("the renew timer", function()
    it("waits for the earliest crossing and wakes the glow without an aura event", function()
        local ns, db = login()
        local D = ns.D
        STATE.units.player = { auras = { armorAura(D, 10), intellect(D, 30) } }
        ns.UpdateBuffState()
        local timers = pending()
        assert.are.equal(1, #timers)
        -- armor: 10 minutes left, renewed 3 before the end; Intellect would come at 25
        local wait = (10 - db.armorRenewMinutes) * 60
        assert.are.equal(wait, timers[1].delay)
        ns.UpdateBuffState()
        assert.are.same({ timers[1] }, pending()) -- the same crossing keeps its timer

        assert.is_false(ns.buttons.Armor.antsShown)
        ADVANCE(wait)
        assert.is_true(ns.buttons.Armor.antsShown)
        -- the next one is Intellect's
        assert.are.equal((30 - db.intellectRenewMinutes) * 60 - wait, pending()[1].delay)
        assert.are.same({}, STATE.errors)
    end)

    it("sets none when nothing will fall due", function()
        local ns = login()
        local D = ns.D
        STATE.units.player = { auras = { D.ARMOR_BUFF_IDS[1], D.SPELL_ARCANE_INTELLECT } }
        ns.UpdateBuffState()
        assert.are.same({}, pending())
    end)

    it("writes nothing in combat and catches up when it ends", function()
        local ns, db = login()
        local D = ns.D
        STATE.units.player = { auras = { armorAura(D, 10), intellect(D, 30) } }
        ns.UpdateBuffState()
        FIRE("PLAYER_REGEN_DISABLED")
        STATE.combat = true
        ADVANCE((10 - db.armorRenewMinutes) * 60)
        assert.is_false(ns.buttons.Armor.antsShown)
        STATE.combat = false
        FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_true(ns.buttons.Armor.antsShown)
        assert.are.same({}, STATE.errors)
    end)
end)

-- The slider row with this label text, and the slider and input box in it (a section header
-- may carry the same text, so only rows holding a slider count)
local function rowOf(label)
    local function parts(frame)
        local slider, box
        for _, c in ipairs(frame.children) do
            if c.kind == "Slider" then slider = c elseif c.kind == "EditBox" then box = c end
        end
        return slider, box
    end
    local function find(frame)
        local slider, box = parts(frame)
        if slider then
            for _, r in ipairs(frame.regions) do if r.text == label then return frame, slider, box end end
        end
        for _, c in ipairs(frame.children) do
            local row, s, b = find(c)
            if row then return row, s, b end
        end
    end
    return find(SimpleConjureBarSettings)
end

describe("the renew sliders", function()
    it("sit side by side below Mana Gem, each writing its key, clamped", function()
        local ns, db = login()
        local D, L = ns.D, ns.L
        ns.ToggleSettings()
        local intelRow, intelSlider, intelBox = rowOf(ns.LocalName(ns.SpellName(D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT"))
        local armorRow, armorSlider, armorBox = rowOf(L.ARMOR)
        assert.is_not_nil(intelRow); assert.is_not_nil(intelBox); assert.is_not_nil(intelSlider)
        assert.is_not_nil(armorRow); assert.is_not_nil(armorBox); assert.is_not_nil(armorSlider)
        local _, ix, iy = intelRow:GetPoint() -- TOPLEFT, x, y
        local _, ax, ay = armorRow:GetPoint()
        assert.are.equal(iy, ay)
        assert.is_true(ax > ix)
        -- on the Tracking page, below the Mana Gem header and under their own
        local page = intelRow:GetParent()
        local function headerY(text)
            for _, r in ipairs(page.regions) do
                if r.text == text then return select(3, r:GetPoint()) end
            end
        end
        local gemY, renewY = headerY(L.MANA_GEM), headerY(L.RENEW_LABEL)
        assert.is_not_nil(gemY); assert.is_not_nil(renewY)
        assert.is_true(gemY > renewY and renewY > iy)
        assert.are.equal(page, armorRow:GetParent())

        intelBox:SetText("99"); RUNSCRIPT(intelBox, "OnEnterPressed")
        assert.are.equal(D.INTELLECT_RENEW_MAX, db.intellectRenewMinutes)
        armorBox:SetText("1"); RUNSCRIPT(armorBox, "OnEnterPressed")
        assert.are.equal(1, db.armorRenewMinutes)
        RUNSCRIPT(armorSlider, "OnValueChanged", 4)
        assert.are.equal(4, db.armorRenewMinutes)
        assert.are.same({}, STATE.errors)
    end)
end)

describe("the renew times", function()
    it("are in settings version 4 with their defaults, clamped and kept", function()
        local ns, db = login({ dbVersion = 3 })
        local D = ns.D
        assert.are.same({ D.VALUE_DEFAULTS.intellectRenewMinutes, D.VALUE_DEFAULTS.armorRenewMinutes },
            { db.intellectRenewMinutes, db.armorRenewMinutes })
        assert.are.same({ 5, 3 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        db = select(2, login({ dbVersion = 4, intellectRenewMinutes = "x", armorRenewMinutes = "x" }))
        assert.are.same({ 5, 3 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        db = select(2, login({ dbVersion = 4, intellectRenewMinutes = 99, armorRenewMinutes = 99 }))
        assert.are.same({ D.INTELLECT_RENEW_MAX, D.ARMOR_RENEW_MAX }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        db = select(2, login({ dbVersion = 4, intellectRenewMinutes = -1, armorRenewMinutes = -1 }))
        assert.are.same({ 0, 0 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
        -- twice without change
        local saved = { dbVersion = 4, intellectRenewMinutes = 7, armorRenewMinutes = 2 }
        db = select(2, login(saved))
        db = select(2, login(db))
        assert.are.same({ 7, 2 }, { db.intellectRenewMinutes, db.armorRenewMinutes })
    end)
end)

-- ruleset plan 2026-10-23-intellect-range, phase 3
describe("the Brilliance threshold", function()
    it("is a setting of version 4, default 3, clamped to 1-never and kept", function()
        local ns, db = login({ dbVersion = 4 })
        local D = ns.D
        assert.are.equal(D.VALUE_DEFAULTS.brillianceThreshold, db.brillianceThreshold)
        assert.are.equal(3, db.brillianceThreshold)
        db = select(2, login({ dbVersion = 4, brillianceThreshold = "x" }))
        assert.are.equal(3, db.brillianceThreshold)
        db = select(2, login({ dbVersion = 4, brillianceThreshold = 99 }))
        assert.are.equal(D.BRILLIANCE_NEVER, db.brillianceThreshold)
        db = select(2, login({ dbVersion = 4, brillianceThreshold = 0 }))
        assert.are.equal(1, db.brillianceThreshold)
        db = select(2, login(select(2, login({ dbVersion = 4, brillianceThreshold = 5 }))))
        assert.are.equal(5, db.brillianceThreshold)
    end)

    it("has a slider below the renew sliders that shows never at its end", function()
        local ns, db = login()
        local D, L = ns.D, ns.L
        ns.ToggleSettings()
        local row, slider, box = rowOf(L.OPT_BRILLIANCE_THRESHOLD)
        assert.is_not_nil(row); assert.is_not_nil(slider); assert.is_not_nil(box)
        local intelRow = rowOf(ns.LocalName(ns.SpellName(D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT"))
        assert.are.equal(intelRow:GetParent(), row:GetParent())
        assert.is_true(select(3, row:GetPoint()) < select(3, intelRow:GetPoint()))
        RUNSCRIPT(slider, "OnValueChanged", D.BRILLIANCE_NEVER)
        assert.are.equal(D.BRILLIANCE_NEVER, db.brillianceThreshold)
        assert.are.equal(L.OPT_NEVER, box:GetText())
        box:SetText("2"); RUNSCRIPT(box, "OnEnterPressed")
        assert.are.equal(2, db.brillianceThreshold)
        assert.are.equal("2", box:GetText())
        assert.are.same({}, STATE.errors)
    end)

    it("opens the settings on the Tracking tab when asked", function()
        local ns = login()
        local row = rowOf(ns.L.OPT_BRILLIANCE_THRESHOLD)
        ns.OpenSettings(nil, "TAB_TRACKING")
        assert.is_true(SimpleConjureBarSettings:IsShown())
        assert.is_true(row:GetParent():IsShown())
    end)
end)

describe("the solo count line", function()
    it("names the case without a number", function()
        local ns = login()
        local D, L = ns.D, ns.L
        local name = ns.LocalName(ns.SpellName(D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT")
        local lowest = D.INTELLECT_RANKS[#D.INTELLECT_RANKS].id
        for key, auras in pairs({
            SELF_MISSING = {}, SELF_WEAKER = { intellect(D, 30, lowest) }, SELF_EXPIRING = { intellect(D, 2) },
        }) do
            STATE.units.player = { auras = auras }
            ns.UpdateBuffState()
            assert.are.equal(L[key]:format(name), ns.buttons.Intellect.hint2, key)
        end
    end)
end)

-- ruleset plan 2026-10-23-intellect-range, phase 4
describe("the Intellect recommendation", function()
    local function name(ns) return ns.LocalName(ns.SpellName(ns.D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT") end

    it("counts and targets only members in range, and names the others", function()
        local ns = login()
        local D, L, b = ns.D, ns.L, ns.buttons.Intellect
        STATE.units.player = { auras = { intellect(D, 30) } }
        STATE.units.party1 = { class = "PRIEST" }
        STATE.units.party2 = { class = "PRIEST", range = false }
        STATE.units.party3 = { class = "PRIEST", range = false }
        regroup(ns, true, false, 4)
        assert.are.equal("1", tostring(b.count:GetText()))
        assert.is_true(b.antsShown)
        assert.are.equal("party1", b:GetAttribute("unit1"))
        assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        assert.are.equal(L.BUFF_MISSING_FAR:format(name(ns), 3, 2), b.hint2)

        STATE.units.party1 = { class = "PRIEST", range = false }
        ns.UpdateBuffState()
        assert.are.equal("", tostring(b.count:GetText()))
        assert.is_false(b.antsShown)
        assert.is_nil(b:GetAttribute("type1"))
        assert.is_nil(b:GetAttribute("unit1"))
        assert.is_truthy(b.hintLeft:find(L.NONE_IN_RANGE, 1, true), b.hintLeft)
        assert.are.equal(L.BUFF_MISSING_FAR:format(name(ns), 3, 3), b.hint2)
    end)

    it("casts Brilliance from the threshold on, else the single buff", function()
        local ns, db = login()
        local D, b = ns.D, ns.buttons.Intellect
        -- three in need in range: Brilliance on the player
        STATE.units.party1 = { class = "PRIEST" }
        STATE.units.party2 = { class = "PRIEST" }
        regroup(ns, true, false, 3)
        assert.are.same({ D.SPELL_ARCANE_BRILLIANCE, "player" }, { b:GetAttribute("spell1"), b:GetAttribute("unit1") })
        -- two (the player buffed, two arrive later): the single buff
        STATE.units.player = { auras = { intellect(D, 30) } }
        ns.UpdateBuffState()
        assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        assert.are.equal("party1", b:GetAttribute("unit1"))
        -- threshold 1: one is enough; never: not even three
        db.brillianceThreshold = 1; ns.UpdateBuffState()
        assert.are.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        STATE.units.player = {}
        db.brillianceThreshold = D.BRILLIANCE_NEVER; ns.UpdateBuffState()
        assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        -- the right click casts nothing in a group
        assert.is_nil(b:GetAttribute("type2"))
    end)

    it("gives a raid subgroup Brilliance for three missing or weaker in range only", function()
        local ns = login()
        local D, b = ns.D, ns.buttons.Intellect
        local lowest = D.INTELLECT_RANKS[#D.INTELLECT_RANKS].id
        for i = 1, 10 do STATE.units["raid" .. i] = { class = "PRIEST", auras = { intellect(D, 30) } } end
        STATE.units.raid6 = { class = "PRIEST" }
        STATE.units.raid7 = { class = "PRIEST", auras = { intellect(D, 30, lowest) } }
        STATE.units.raid8 = { class = "PRIEST" }
        regroup(ns, true, true, 10)
        assert.are.same({ D.SPELL_ARCANE_BRILLIANCE, "raid6" }, { b:GetAttribute("spell1"), b:GetAttribute("unit1") })
        -- three only expiring: no Brilliance
        for _, u in ipairs({ "raid6", "raid7", "raid8" }) do STATE.units[u] = { class = "PRIEST", auras = { intellect(D, 1) } } end
        ns.UpdateBuffState()
        assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        -- a far member never counts toward a subgroup
        STATE.units.raid6 = { class = "PRIEST" }
        STATE.units.raid7 = { class = "PRIEST" }
        STATE.units.raid8 = { class = "PRIEST", range = false }
        ns.UpdateBuffState()
        assert.are_not.equal(D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
    end)

    it("has no right click solo, and opens the threshold in a group", function()
        local ns = login()
        local L, b = ns.L, ns.buttons.Intellect
        regroup(ns, false, false, 0)
        assert.is_nil(b:GetAttribute("type2"))
        assert.is_nil(b.hintKey or b.hint)
        regroup(ns, true, false, 3)
        assert.are.equal("HINT_THRESHOLD", b.hintKey)
        SimpleConjureBarSettings:Hide()
        STATE.casts = {}
        RUNCLICK(b, "RightButton", true); RUNCLICK(b, "RightButton", false)
        assert.is_true(SimpleConjureBarSettings:IsShown())
        assert.are.same({}, STATE.casts)
        assert.is_truthy(L.HINT_THRESHOLD)
    end)

    it("shows the group in demo mode, by the threshold", function()
        local ns, db = login()
        local D, L, b = ns.D, ns.L, ns.buttons.Intellect
        db.demo = true; ns.Rebuild(); ns.UpdateBuffState()
        assert.are.equal(tostring(db.brillianceThreshold), tostring(b.count:GetText()))
        assert.are.equal(L.HINT_LEFT:format(ns.SpellName(D.SPELL_ARCANE_BRILLIANCE) .. " > " .. L.TARGET_GROUP), b.hintLeft)
        db.brillianceThreshold = D.BRILLIANCE_NEVER; ns.UpdateBuffState()
        assert.are.equal("1", tostring(b.count:GetText()))
        assert.is_truthy(b.hintLeft:find(UnitName("player"), 1, true), b.hintLeft)
        -- a right click solo says nothing, no "?"
        _G.CHAT = {}
        RUNCLICK(b, "RightButton", true); RUNCLICK(b, "RightButton", false)
        assert.are.same({}, CHAT)
        db.demo = false; ns.Rebuild()
    end)
end)
