-- The Intellect tooltip names what each click casts and on whom, the left click too; a left
-- click on the handle in combat says why nothing happens
-- (ruleset plan 2026-10-21-bar-alignment, items 2 and 3).

local addon = require("addon")

local function login()
    _G.SimpleConjureBarDB = nil
    local ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns
end

-- The lines the Intellect button's tooltip adds, in order
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

local function regroup(ns, group, raid, members)
    STATE.group, STATE.raid, STATE.members = group, raid, members
    FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
    ns.UpdateBuffState()
end

describe("the Intellect tooltip", function()
    it("names no target solo", function()
        local ns = login()
        regroup(ns, false, false, 0)
        local b, L = ns.buttons.Intellect, ns.L
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1")))))
    end)

    it("names the member a single buff goes to, and Brilliance's group, in a party", function()
        local ns = login()
        local b, L = ns.buttons.Intellect, ns.L
        regroup(ns, true, false, 3)
        -- Brilliance on the left in a group, while it is known and powder is in the bags
        assert.are.equal(ns.D.SPELL_ARCANE_BRILLIANCE, b:GetAttribute("spell1"))
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(ns.D.SPELL_ARCANE_BRILLIANCE)
            .. " > " .. L.TARGET_GROUP)), table.concat(lines, " | "))

        -- Without powder the left click is the single buff, on a member by name
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 0
        ns.UpdateBuffState()
        local unit = b:GetAttribute("unit1")
        lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(b:GetAttribute("spell1"))
            .. " > " .. UnitName(unit))), table.concat(lines, " | "))
        ITEMS[ns.D.ITEM_ARCANE_POWDER] = 5
    end)

    it("names Brilliance's subgroup by number in a raid", function()
        local ns = login()
        local b, L = ns.buttons.Intellect, ns.L
        regroup(ns, true, true, 12)
        local unit = b:GetAttribute("unit1")
        local index = tonumber(unit:match("^raid(%d+)$"))
        assert.is_not_nil(index, unit)
        local sub = select(3, GetRaidRosterInfo(index))
        local lines = tooltipLines(ns)
        assert.is_true(has(lines, L.HINT_LEFT:format(ns.SpellName(ns.D.SPELL_ARCANE_BRILLIANCE)
            .. " > " .. L.TARGET_SUBGROUP:format(sub))), table.concat(lines, " | "))
        assert.are.same({}, STATE.errors)
    end)
end)

-- The click lines of a button's tooltip, in order, after its spacer
local function clickLines(ns, button)
    local lines, started = {}, false
    GameTooltip.AddLine = function(_, text)
        if text == " " then started = true elseif started then lines[#lines + 1] = text end
    end
    ns.ShowTooltip(button)
    return lines
end

describe("every button's tooltip", function()
    it("lists left, middle and right click in that order, extras after them", function()
        local ns = login()
        local L, b = ns.L, ns.buttons
        ns.Rebuild(); RUNTIMERS()
        local cast = L.HINT_CAST_SPELL:format(ns.SpellName(b.Armor:GetAttribute("spell1")))
        assert.are.same({ cast, L.HINT_PICK_ARMOR }, clickLines(ns, b.Armor))
        assert.are.same({ L.HINT_TELEPORT, L.HINT_PICK }, clickLines(ns, b.Teleport))
        assert.are.same({ L.HINT_PORTAL, L.HINT_PICK }, clickLines(ns, b.Portal))
        local gem = clickLines(ns, b.ManaGem)
        assert.are.equal(L.HINT_USE_ITEM:format(C_Item.GetItemNameByID(b.ManaGem.leftItem)), gem[1])
        assert.are.equal(L.HINT_RIGHT:format(ns.SpellName(b.ManaGem.conjureSpell)), gem[2])
        for _, key in ipairs({ "Water", "Food" }) do
            local lines = clickLines(ns, b[key])
            assert.are.same({ b[key].hintLeft, L.HINT_MIDDLE, b[key].hint }, lines, key)
        end
        STATE.units.player = {} -- Intellect missing: the count follows the clicks
        ns.UpdateBuffState()
        local intel = clickLines(ns, b.Intellect)
        -- solo no right click; the line names the case (ruleset plan 2026-10-23-intellect-range)
        assert.are.same({ b.Intellect.hintLeft, L.HINT_BUFF_RUN }, { intel[1], intel[2] })
        assert.are.equal(b.Intellect.hint2, intel[3]) -- "Missing: Arcane Intellect"
        assert.is_nil(intel[4])
        -- set apart from the clicks by an empty line (Michel)
        local raw = {}
        GameTooltip.AddLine = function(_, text) raw[#raw + 1] = text end
        ns.ShowTooltip(b.Intellect)
        assert.are.equal(" ", raw[#raw - 1])
        assert.are.equal(intel[3], raw[#raw])
        assert.is_truthy(L.HINT_PICK_ARMOR:find("Choose Armor", 1, true))
        assert.is_truthy(L.HINT_PICK:find("Choose Destination", 1, true))
        assert.are.same({}, STATE.errors)
    end)

    -- One format on every tooltip: single green lines, in combat only what works there
    -- (ruleset plan 2026-10-25-chat-and-docked-report)
    it("give the handle, the minimap button and the menu entry single click lines", function()
        local ns = login()
        local L = ns.L
        local entry = NEWOBJ("Frame", "menuEntry")
        local function shown(show)
            local lines = {}
            GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
            GameTooltip.AddDoubleLine = function() lines[#lines + 1] = "double line" end
            show()
            return lines
        end
        local function handle() return shown(function() RUNSCRIPT(ns.handle, "OnEnter") end) end
        local function minimap() return shown(function() RUNSCRIPT(SimpleConjureBarMinimapButton, "OnEnter") end) end
        local function menu() return shown(function() ns.CompartmentEnter(nil, entry) end) end
        local function hasLine(lines, wanted) for _, l in ipairs(lines) do if l == wanted then return true end end end
        local function hasNo(lines, wanted) return not hasLine(lines, wanted) end

        SimpleConjureBarDB.locked = false
        local h = handle()
        assert.is_true(hasLine(h, L.HINT_LEFT:format(L.MOVE)), table.concat(h, " | "))
        assert.is_true(hasLine(h, L.HINT_MIDDLE_CLICK:format(L.SETTINGS)))
        assert.is_true(hasLine(h, L.HINT_RIGHT:format(L.LOCK)))
        assert.is_true(hasNo(h, "double line"))
        SimpleConjureBarDB.locked = true
        h = handle()
        assert.is_true(hasNo(h, L.HINT_LEFT:format(L.MOVE))) -- a locked bar does not move
        assert.is_true(hasLine(h, L.HINT_RIGHT:format(L.UNLOCK)))
        local m = minimap()
        assert.is_true(hasLine(m, L.HINT_LEFT:format(L.SETTINGS)), table.concat(m, " | "))
        assert.is_true(hasLine(m, L.HINT_RIGHT:format(L.UNLOCK_BAR)))
        assert.is_true(hasLine(m, L.HINT_DRAG:format(L.MOVE)))
        local e = menu()
        assert.is_true(hasLine(e, L.HINT_LEFT:format(L.SETTINGS)))
        assert.is_true(hasNo(e, L.HINT_DRAG:format(L.MOVE)))

        STATE.combat = true -- only the clicks that work there
        h, m, e = handle(), minimap(), menu()
        assert.is_true(hasNo(h, L.HINT_MIDDLE_CLICK:format(L.SETTINGS)))
        assert.is_true(hasLine(h, L.HINT_RIGHT:format(L.UNLOCK)))
        assert.is_true(hasNo(m, L.HINT_LEFT:format(L.SETTINGS)))
        assert.is_true(hasLine(m, L.HINT_RIGHT:format(L.UNLOCK_BAR)))
        assert.is_true(hasLine(m, L.HINT_DRAG:format(L.MOVE)))
        assert.is_true(hasNo(e, L.HINT_LEFT:format(L.SETTINGS)))
        assert.is_true(hasLine(e, L.HINT_RIGHT:format(L.UNLOCK_BAR)))
        STATE.combat = false

        ns.ApplyLanguage("deDE") -- read on every show: a language switch follows at once
        local de = ns.locales.deDE
        assert.is_true(hasLine(minimap(), de.HINT_LEFT:format(de.SETTINGS)))
        ns.ApplyLanguage("enUS")
        assert.are.same({}, STATE.errors)
    end)
end)

describe("the water and food tooltips", function()
    it("name the left click's use and the middle click's trade", function()
        local ns = login()
        local L = ns.L
        for key, use in pairs({ Water = "HINT_USE_WATER", Food = "HINT_USE_FOOD" }) do
            local lines = {}
            GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
            ns.ShowTooltip(ns.buttons[key])
            assert.is_true(has(lines, L[use]), key .. ": " .. table.concat(lines, " | "))
            assert.is_true(has(lines, L.HINT_MIDDLE), key)
            assert.are.equal(L[use], lines[2], key .. ": the left click first") -- after the spacer
        end
        assert.is_truthy(L.HINT_MIDDLE:find("Trade Food & Water", 1, true))
    end)
end)

-- The client answers an item's name only once its data is loaded; before that the gem's line
-- read "Use ?" until the next rebuild (seen in game, 2026-10-23, demo mode without a gem)
describe("the mana gem's tooltip", function()
    it("names the gem once the client has loaded its data", function()
        local loaded, requested = false, {}
        _G.SimpleConjureBarDB = nil
        local ns = addon.load("enUS", function()
            local name = C_Item.GetItemNameByID
            C_Item.GetItemNameByID = function(id) if loaded then return name(id) end end
            C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
        end)
        FIRE("PLAYER_LOGIN"); RUNTIMERS()
        local gem, L = ns.buttons.ManaGem, ns.L
        assert.is_not_nil(gem.leftItem)
        assert.are.same({ gem.leftItem }, requested)
        loaded = true
        FIRE("ITEM_DATA_LOAD_RESULT", gem.leftItem, true)
        assert.are.equal(L.HINT_USE_ITEM:format(C_Item.GetItemNameByID(gem.leftItem)), gem.hintLeft)
        assert.are.same({}, STATE.errors)
    end)
end)

describe("the minimap button's tooltip", function()
    it("says the right click locks or unlocks the bar, and follows the click at once", function()
        local ns = login()
        local L = ns.L
        local button = SimpleConjureBarMinimapButton
        local right
        GameTooltip.AddLine = function(_, text)
            if text == L.HINT_RIGHT:format(L.LOCK_BAR) then right = L.LOCK_BAR end
            if text == L.HINT_RIGHT:format(L.UNLOCK_BAR) then right = L.UNLOCK_BAR end
        end
        SimpleConjureBarDB.locked = false
        RUNSCRIPT(button, "OnEnter")
        assert.are.equal(L.LOCK_BAR, right)
        RUNSCRIPT(button, "OnClick", "RightButton")
        assert.is_true(SimpleConjureBarDB.locked)
        assert.are.equal(L.UNLOCK_BAR, right) -- without leaving the button
        RUNSCRIPT(button, "OnLeave")
        right = nil
        RUNSCRIPT(button, "OnClick", "RightButton")
        assert.is_nil(right) -- no tooltip opened by a click when the mouse is gone
    end)
end)

describe("the handle", function()
    -- chat speaks only for demo mode and commands (ruleset plan 2026-10-25-chat-and-docked-report)
    it("stays quiet for a left click in combat, and does not move", function()
        local ns = login()
        SimpleConjureBarDB.locked = false
        _G.CHAT = {}
        STATE.combat = true
        RUNSCRIPT(ns.handle, "OnMouseDown", "LeftButton")
        assert.are.same({}, CHAT)
        assert.is_falsy(ns.handle.moving)
        STATE.combat = false
    end)
end)

-- In combat a tooltip lists only the clicks that work there (ruleset plan 2026-10-25-combat-locks,
-- item 2)
describe("a tooltip in combat", function()
    it("leaves out the lines of the clicks locked there, and has them back after", function()
        local ns = login()
        local L, b = ns.L, ns.buttons
        STATE.units.player = {} -- Intellect missing: it has a bottom line
        ns.UpdateBuffState()
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        assert.are.same({}, clickLines(ns, b.Intellect))
        assert.are.same({}, clickLines(ns, b.Water))
        assert.are.same({}, clickLines(ns, b.Food))
        assert.are.same({ b.ManaGem.hintLeft }, clickLines(ns, b.ManaGem))
        assert.are.same({ L.HINT_PICK }, clickLines(ns, b.Teleport))
        assert.are.same({ L.HINT_PICK }, clickLines(ns, b.Portal))
        local cast = L.HINT_CAST_SPELL:format(ns.SpellName(b.Armor:GetAttribute("spell1")))
        assert.are.same({ cast, L.HINT_PICK_ARMOR }, clickLines(ns, b.Armor))

        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.are.same({ b.Water.hintLeft, L.HINT_MIDDLE, b.Water.hint }, clickLines(ns, b.Water))
        assert.are.same({ b.ManaGem.hintLeft, b.ManaGem.hint }, clickLines(ns, b.ManaGem))
        assert.are.same({ L.HINT_TELEPORT, L.HINT_PICK }, clickLines(ns, b.Teleport))
        assert.are.equal(b.Intellect.hint2, clickLines(ns, b.Intellect)[3])
        assert.are.same({}, STATE.errors)
    end)
end)

-- The armor's line names the armor a left click casts (ruleset plan 2026-10-25-combat-locks,
-- item 7)
describe("the armor tooltip", function()
    it("names the chosen armor, also after a choice in combat", function()
        local ns = login()
        local L, armor = ns.L, ns.buttons.Armor
        local function cast(id) return L.HINT_CAST_SPELL:format(ns.SpellName(id)) end
        assert.are.equal(cast(armor:GetAttribute("spell1")), clickLines(ns, armor)[1])
        RUNCLICK(armor, "RightButton", false)
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        local other = armor.fly.buttons[2]
        RUNCLICK(other, "LeftButton", false)
        assert.are.equal(cast(other:GetAttribute("spell")), clickLines(ns, armor)[1])
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_truthy(L.HINT_CAST_SPELL:find("%s", 1, true))
        assert.are.same({}, STATE.errors)
    end)
end)
