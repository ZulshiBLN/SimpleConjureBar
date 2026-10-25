-- SimpleConjureBar - button setup and bar layout
-- Fills the buttons with the right spells/items, lays out the bar and keeps counts up to date.
-- Secure attributes can only change out of combat; changes during combat are queued.

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local SIZE, GAP, PAD = D.SIZE, D.GAP, D.PAD
local ItemCount, ItemIcon, ItemName, GetSpellTex = API.ItemCount, API.ItemIcon, API.ItemName, API.GetSpellTex
local IsDemo, IsKnown, SetAttr = ns.IsDemo, ns.IsKnown, ns.SetAttr

local bar, handle, buttons = ns.bar, ns.handle, ns.buttons
local water, food, gem = buttons.Water, buttons.Food, buttons.ManaGem
local tele, portal, armor, intel = buttons.Teleport, buttons.Portal, buttons.Armor, buttons.Intellect

local db
ns.OnDBReady(function(d) db = d end)

local WATER_FOOD  = { water, food }
local TELE_PORTAL = { tele, portal }
local WHITE = { r = 1, g = 1, b = 1, a = 1 }

---------------------------------------------------------------------------
-- Counts (cheap, also runs in combat)
---------------------------------------------------------------------------
function ns.UpdateCounts()
    if not db then return end
    for _, b in ipairs(WATER_FOOD) do
        if b:IsShown() and b.leftItem then
            b.count:SetText(b.fakeCount and 20 or (ItemCount(b.leftItem) or 0))
        else
            b.count:SetText("")
        end
    end

    -- Rune count on Teleport/Portal: white, warning color at/below the threshold, empty color at 0
    for _, b in ipairs(TELE_PORTAL) do
        if b:IsShown() then
            local n = IsDemo() and (b == tele and 3 or 0) or (ItemCount(b.rune) or 0)
            local c = WHITE
            if n == 0 then c = db.runeZeroColor
            elseif db.runeWarn > 0 and n <= db.runeWarn then c = db.runeWarnColor end
            b.count:SetText(n)
            b.count:SetTextColor(c.r, c.g, c.b, c.a)
        else
            b.count:SetText("")
        end
    end

    -- Mana Gem: highlight without a gem, cooldown of the best gem
    if gem:IsShown() then
        local owned
        if not IsDemo() then -- in demo mode the gem highlight shows like the other highlights
            for _, g in ipairs(D.MANA_GEMS) do
                if (ItemCount(g.item) or 0) > 0 then owned = g.item break end
            end
        end
        ns.SetAnts(gem, not owned)
        local start, duration = 0, 0
        if owned and API.ItemCooldown then start, duration = API.ItemCooldown(owned) end
        if start and duration and duration > 1.5 then
            gem.cooldown:SetCooldown(start, duration)
        else
            gem.cooldown:Clear()
        end
    end
end
local UpdateCounts = ns.UpdateCounts

---------------------------------------------------------------------------
-- Mana Gem: left = best owned gem, right = conjure the highest missing gem.
-- Left click runs a macro, so it keeps working in combat after the best gem was used
-- (attributes cannot change in combat). It lists the owned gems first (best first), then the
-- known but missing gems, so a gem conjured during combat can be used right away. With several
-- gems a later line can still report the shared cooldown or a missing item, which is accepted.
---------------------------------------------------------------------------
-- An item's name reads nil until the client has loaded its data - in demo mode, say, with no gem
-- in the bags. The gem's line then waits for ITEM_DATA_LOAD_RESULT instead of showing "?".
local requestedNames = {}
local function GemName(item)
    local name = ItemName(item)
    if not name and not requestedNames[item] and C_Item and C_Item.RequestLoadItemDataByID then
        requestedNames[item] = true
        C_Item.RequestLoadItemDataByID(item)
    end
    return name or "?"
end

local function SetupGem(b)
    local knownGems, ownedLines, missingLines = {}, {}, {}
    local owned, conjure
    for _, g in ipairs(D.MANA_GEMS) do
        if IsKnown(g.spell) then
            knownGems[#knownGems + 1] = g
            local has = (ItemCount(g.item) or 0) > 0
            if has then
                owned = owned or g.item
                ownedLines[#ownedLines + 1] = "/use item:" .. g.item
            else
                missingLines[#missingLines + 1] = "/use item:" .. g.item
                conjure = conjure or g.spell
            end
        end
    end
    if #knownGems == 0 then b:Hide() return false end
    conjure = conjure or knownGems[1].spell -- all gems owned: conjure the highest
    for _, line in ipairs(missingLines) do ownedLines[#ownedLines + 1] = line end
    if IsDemo() and not owned then owned = knownGems[1].item end

    b.leftItem, b.conjureSpell = owned, conjure
    b.spellId = not owned and conjure or nil
    -- Left uses the best gem; without one it conjures, and the line says so
    b.hintLeft = owned and L.HINT_USE_ITEM:format(GemName(owned))
        or L.HINT_LEFT:format(ns.SpellName(conjure) or L.CONJURE)
    b.hint = L.HINT_RIGHT:format(ns.SpellName(conjure) or L.CONJURE)

    if IsDemo() then
        SetAttr(b, "type1", nil)
        SetAttr(b, "type2", nil)
    else
        if owned then
            SetAttr(b, "type1", "macro")
            SetAttr(b, "macrotext1", table.concat(ownedLines, "\n"))
        else
            SetAttr(b, "type1", "spell")
            SetAttr(b, "spell1", conjure)
        end
        SetAttr(b, "type2", "spell")
        SetAttr(b, "spell2", conjure)
    end
    b.icon:SetTexture(owned and ItemIcon(owned) or GetSpellTex(conjure))
    b:Show()
    return true
end

---------------------------------------------------------------------------
-- Water / Food: left = consume the best item, right = conjure (rank fitting the target)
---------------------------------------------------------------------------
-- Conjure part only; also used on target changes without a full rebuild
local function ApplyConjure(b)
    local conjure, forLevel = ns.ConjureSpellFor(b.spells, b.items)
    b.conjureSpell = conjure
    b.hint = L.HINT_RIGHT:format(ns.SpellName(conjure) or L.CONJURE)
    if forLevel and conjure ~= b.spellId then
        b.hint = b.hint .. L.HINT_RANK_FOR:format(forLevel)
    end
    if not IsDemo() then
        SetAttr(b, "type2", "spell")
        SetAttr(b, "spell2", conjure)
    end
end

local function SetupConsumable(b)
    local spell = ns.BestSpell(b.spells)
    if not spell then b:Hide() return false end
    local item = ns.BestItem(b.items)
    b.fakeCount = false
    if IsDemo() and not item then
        item, b.fakeCount = b.items[1], true -- simulated best water/food
    end
    b.leftItem, b.spellId = item, spell
    -- The left click uses the best item; without one it conjures, and the line says so
    if item then
        b.hintLeft = b == water and L.HINT_USE_WATER or L.HINT_USE_FOOD
    else
        b.hintLeft = L.HINT_LEFT:format(ns.SpellName(spell) or L.CONJURE)
    end
    b.hintMiddle = L.HINT_MIDDLE
    if IsDemo() then
        -- No real action, only the demo message
        SetAttr(b, "type1", nil)
        SetAttr(b, "type2", nil)
    elseif item then
        SetAttr(b, "type1", "item")
        SetAttr(b, "item1", "item:" .. item)
    else
        SetAttr(b, "type1", "spell")
        SetAttr(b, "spell1", spell)
    end
    ApplyConjure(b)
    b.icon:SetTexture(item and ItemIcon(item) or GetSpellTex(spell))
    b:Show()
    return true
end

---------------------------------------------------------------------------
-- Flyout buttons (Armor, Teleport, Portal)
---------------------------------------------------------------------------
-- Flyout direction: a fixed side from the settings, or automatic - horizontal bars open
-- upwards (downwards in the upper half of the screen), vertical bars open to the right (to the
-- left in the right half of the screen)
local flyDir = "UP"
local function ComputeFlyDir()
    if db.flyoutDir == "FIRST" then return db.vertical and "RIGHT" or "UP" end
    if db.flyoutDir == "SECOND" then return db.vertical and "LEFT" or "DOWN" end
    local cx, cy = bar:GetCenter()
    if not cx then return db.vertical and "RIGHT" or "UP" end
    local s = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    cx, cy = cx * s, cy * s
    if db.vertical then
        return (cx > UIParent:GetWidth() / 2) and "LEFT" or "RIGHT"
    end
    return (cy > UIParent:GetHeight() / 2) and "DOWN" or "UP"
end

local FLY_LAYOUT = {
    UP    = { fly = { "BOTTOM", "TOP", 0, 6 },  child = "BOTTOM", dx = 0,  dy = 1,  arrow = { "BOTTOM", "TOP", 0, -6 }, rot = 0 },
    DOWN  = { fly = { "TOP", "BOTTOM", 0, -6 }, child = "TOP",    dx = 0,  dy = -1, arrow = { "TOP", "BOTTOM", 0, 6 },  rot = math.pi },
    RIGHT = { fly = { "LEFT", "RIGHT", 6, 0 },  child = "LEFT",   dx = 1,  dy = 0,  arrow = { "LEFT", "RIGHT", -6, 0 }, rot = -math.pi / 2 },
    LEFT  = { fly = { "RIGHT", "LEFT", -6, 0 }, child = "RIGHT",  dx = -1, dy = 0,  arrow = { "RIGHT", "LEFT", 6, 0 },  rot = math.pi / 2 },
}

-- The seconds a flyout stays open after the mouse left it and its button, read by the secure
-- right-click snippet (Bar.lua). The header is protected: written out of combat only.
function ns.ApplyAutoClose()
    if InCombatLockdown() then return end
    SetAttr(ns.header, "autohide", db.flyoutAutoClose)
end

local function SetupFlyout(main)
    local known = main.listFn()
    if #known == 0 then
        main.fly:Hide()
        main:Hide()
        return false
    end

    local sel = db.last[main.key]
    if sel and main.normalize then sel = main.normalize(sel) end
    local valid = false
    for _, id in ipairs(known) do if id == sel then valid = true break end end
    if not valid then sel = known[1] end
    main.spellId = sel
    SetAttr(main, "type1", (not IsDemo()) and "spell" or nil)
    SetAttr(main, "spell1", sel)
    main.icon:SetTexture(GetSpellTex(sel))
    if main.label then main.label:SetText(ns.ArmorShortName(sel)) end

    local lay = FLY_LAYOUT[flyDir]
    main.fly:ClearAllPoints()
    main.fly:SetPoint(lay.fly[1], main, lay.fly[2], lay.fly[3], lay.fly[4])
    main.arrow:ClearAllPoints()
    main.arrow:SetPoint(lay.arrow[1], main, lay.arrow[2], lay.arrow[3], lay.arrow[4])
    main.arrow:SetRotation(lay.rot)

    local lc = db.armorLabelColor
    for i, id in ipairs(known) do
        local c = ns.GetFlyoutChild(main, i)
        c.spellId = id
        -- An icon only chooses (no "type", so a click casts nothing); its secure snippet hands
        -- the spell to the main button, which casts it (Bar.lua GetFlyoutChild)
        SetAttr(c, "spell", id)
        c.icon:SetTexture(GetSpellTex(id))
        if c.label then
            c.label:SetText(ns.ArmorShortName(id))
            c.label:SetTextColor(lc.r, lc.g, lc.b, lc.a)
        end
        c:ClearAllPoints()
        local off = PAD + (i - 1) * (SIZE + GAP)
        c:SetPoint(lay.child, main.fly, lay.child, lay.dx * off, lay.dy * off)
        c:Show()
    end
    for i = #known + 1, #main.fly.buttons do main.fly.buttons[i]:Hide() end
    local long = #known * (SIZE + GAP) - GAP + 2 * PAD
    if lay.dx ~= 0 then
        main.fly:SetSize(long, SIZE + 2 * PAD)
    else
        main.fly:SetSize(SIZE + 2 * PAD, long)
    end

    main:Show()
    return true
end

---------------------------------------------------------------------------
-- "Cast next buff" key (Bar.lua): the action that clears the first glowing, shown button in the
-- bar's order - Armor's and Intellect's left click, the Mana Gem's right click (conjure). It is
-- set again on every glow change, after a rebuild and a buff update. The key is protected:
-- a change in combat waits for its end, which sets the key again.
---------------------------------------------------------------------------
local KEY_CLICK = { Armor = "1", Intellect = "1", ManaGem = "2" }
function ns.UpdateBuffKey()
    if not db or InCombatLockdown() then return end
    local source, n
    for _, k in ipairs(db.order) do
        local b = buttons[k]
        -- A glowing button whose click has nothing to do - Brilliance with every needy raid group
        -- out of range - is passed, so it hides no missing armor (demo mode writes no types)
        if KEY_CLICK[k] and b:IsShown() and b.antsShown
            and (ns.IsDemo() or b:GetAttribute("type" .. KEY_CLICK[k])) then
            source, n = k, KEY_CLICK[k]
            break
        end
    end
    local key, b = ns.buffKey, source and buttons[source]
    if key:GetAttribute("scbsource") ~= source then ns.Log("buffkey " .. tostring(source)) end
    SetAttr(key, "scbsource", source)
    SetAttr(key, "type1", b and b:GetAttribute("type" .. n) or nil)
    SetAttr(key, "spell1", b and b:GetAttribute("spell" .. n) or nil)
    SetAttr(key, "unit1", b and n == "1" and b:GetAttribute("unit1") or nil)
    -- Demo mode writes no action; a press prints this spell instead
    key.demoSpell = b and (b.isGem and b.conjureSpell or b.leftSpell or b.spellId) or nil
end

-- Combat freezes the key, and in combat it casts the armor only, as the button on the bar does
-- (Michel, 2026-10-21 and 2026-10-25): it takes the armor at combat start when it holds
-- nothing or what is locked there - Intellect, the gem's conjure. PLAYER_REGEN_DISABLED comes
-- right before the lockdown, the last moment the key can be written; Bar.lua calls this after
-- the combat look, and combat's end sets the key from the glow again.
function ns.ArmorForCombat()
    local key = ns.buffKey
    if InCombatLockdown() or key:GetAttribute("scbsource") == "Armor" or not armor:IsShown() then return end
    SetAttr(key, "scbsource", "Armor")
    SetAttr(key, "type1", armor:GetAttribute("type1"))
    SetAttr(key, "spell1", armor:GetAttribute("spell1"))
    SetAttr(key, "unit1", nil)
    key.demoSpell = armor.spellId
end

---------------------------------------------------------------------------
-- Rebuild (out of combat only)
---------------------------------------------------------------------------
-- Each builder returns true when its button is shown
local BUILDERS = {
    Armor     = function() return db.showArmor and SetupFlyout(armor) end,
    Intellect = function() return db.showIntellect and ns.SetupIntellect(intel) end,
    ManaGem   = function() return db.showGem and SetupGem(gem) end,
    Water     = function() return SetupConsumable(water) end,
    Food      = function() return SetupConsumable(food) end,
    Teleport  = function() return SetupFlyout(tele) end,
    Portal    = function() return SetupFlyout(portal) end,
}

local pending = false        -- a rebuild was requested during combat
local conjurePending = false -- the target changed during combat
local shown = {}

function ns.Rebuild()
    if not db then return end
    -- Not before the bar is positioned (Main.lua, after a login in combat): the re-anchoring
    -- would save the start position over the player's. The setup rebuilds.
    if not ns.barReady then pending = true return end
    if InCombatLockdown() then
        pending = true
        UpdateCounts()
        return
    end
    pending = false
    ns.Log("rebuild")

    ns.ReAnchor()
    flyDir = ComputeFlyDir()
    ns.ApplyAutoClose()

    wipe(shown)
    for _, key in ipairs(db.order) do
        local b = buttons[key]
        if BUILDERS[key]() then
            shown[#shown + 1] = b
        else
            if b.fly then b.fly:Hide() end
            b:Hide()
        end
    end

    -- Arrange the buttons starting at the anchor point
    local point = ns.AnchorPoint()
    for i, b in ipairs(shown) do
        local off = PAD + (i - 1) * (SIZE + GAP)
        b:ClearAllPoints()
        if point == "LEFT" then b:SetPoint("LEFT", bar, "LEFT", off, 0)
        elseif point == "RIGHT" then b:SetPoint("RIGHT", bar, "RIGHT", -off, 0)
        elseif point == "TOP" then b:SetPoint("TOP", bar, "TOP", 0, -off)
        else b:SetPoint("BOTTOM", bar, "BOTTOM", 0, off) end
    end
    local long = math.max(1, #shown) * (SIZE + GAP) - GAP + 2 * PAD
    if db.vertical then bar:SetSize(SIZE + 2 * PAD, long) else bar:SetSize(long, SIZE + 2 * PAD) end

    -- The handle sits on the anchor side
    handle:ClearAllPoints()
    if point == "LEFT" then
        handle:SetSize(10, SIZE); handle:SetPoint("RIGHT", bar, "LEFT", -1, 0)
    elseif point == "RIGHT" then
        handle:SetSize(10, SIZE); handle:SetPoint("LEFT", bar, "RIGHT", 1, 0)
    elseif point == "TOP" then
        handle:SetSize(SIZE, 10); handle:SetPoint("BOTTOM", bar, "TOP", 0, 1)
    else
        handle:SetSize(SIZE, 10); handle:SetPoint("TOP", bar, "BOTTOM", 0, -1)
    end
    UpdateCounts()
    ns.UpdateBuffState()
    ns.UpdateBuffKey()
end
local Rebuild = ns.Rebuild

-- Several events often fire in the same frame (bags, spells, roster): rebuild once
local rebuildQueued = false
local function RunQueuedRebuild()
    rebuildQueued = false
    Rebuild()
end
function ns.QueueRebuild()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0, RunQueuedRebuild)
end

-- Target change: only the conjure rank of water and food depends on the target
local function UpdateConjureForTarget()
    if not db then return end
    if InCombatLockdown() then conjurePending = true return end
    conjurePending = false
    for _, b in ipairs(WATER_FOOD) do
        if b:IsShown() and b.spells then ApplyConjure(b) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, ...)
    if not db then return end
    if event == "ITEM_DATA_LOAD_RESULT" then
        -- text only, no attribute: allowed in combat too
        local item, ok = ...
        if ok and gem.leftItem == item then gem.hintLeft = L.HINT_USE_ITEM:format(GemName(item)) end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        UpdateConjureForTarget()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateCounts() -- cooldown and numbers only, no full rebuild
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then
            conjurePending = false
            Rebuild()
        elseif conjurePending then
            UpdateConjureForTarget()
        end
        UpdateCounts() -- the gem's glow, hidden in combat
        ns.UpdateBuffKey() -- drops the Armor of ArmorForCombat, and applies what waited
    else
        ns.QueueRebuild()
    end
end)
