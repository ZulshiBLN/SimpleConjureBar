-- SimpleConjureBar - bar frame and buttons
-- The bar, its drag handle, position/scale/lock handling, the secure buttons with their
-- highlight (the client's proc glow), the flyout menus and the colors.
--
-- Armor          : left = last armor, right = open the armor flyout (choice is remembered)
-- Intellect      : left = the recommendation (Brilliance from the threshold, else the single
--                  buff), right = the threshold (in a group), middle = Buff & Run
-- Mana Gem       : left = best gem, right = conjure a missing gem
-- Water / Food   : left = consume, right = conjure, middle = trade water & food to the target
-- Teleport/Portal: left = last destination, right = open the destinations (choice is remembered)
-- Handle         : left = move, right = lock, middle = settings (also /scb)

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local SIZE, PAD = D.SIZE, D.PAD
local GetSpellTex, ItemName = API.GetSpellTex, API.ItemName
local IsDemo, DemoPrint = ns.IsDemo, ns.DemoPrint

local db
ns.OnDBReady(function(d) db = d end)

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "SimpleConjureBarFrame", UIParent, API.BACKDROP_TPL)
ns.bar = bar
bar:SetSize(SIZE, SIZE)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200) -- start position, replaced at login
if bar.SetBackdrop then
    bar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end

-- Drag handle; visible while the mouse is over it, while dragging or with "Show anchor"
local handle = CreateFrame("Frame", nil, bar)
ns.handle = handle
handle:SetSize(10, SIZE)
handle:SetPoint("RIGHT", bar, "LEFT", -1, 0)
handle:EnableMouse(true)
local handleTex = handle:CreateTexture(nil, "BACKGROUND")
handleTex:SetAllPoints()

function ns.LoadPosition()
    bar:ClearAllPoints()
    bar:SetPoint(db.point or "CENTER", UIParent, db.rel or "CENTER", db.x or 0, db.y or -200)
end

-- The anchor point depends on the growth direction: the bar grows away from this point
-- when buttons are added (right -> left edge, left -> right edge and so on).
function ns.AnchorPoint()
    if db.vertical then return db.growRev and "BOTTOM" or "TOP" end
    return db.growRev and "RIGHT" or "LEFT"
end

-- Re-anchors the bar at its anchor point without moving it on screen, and saves the position
function ns.ReAnchor()
    if InCombatLockdown() then return end
    local l, b, w, h = bar:GetRect()
    if not l then return end
    local point = ns.AnchorPoint()
    local x, y
    if point == "LEFT" then x, y = l, b + h / 2
    elseif point == "RIGHT" then x, y = l + w, b + h / 2
    elseif point == "TOP" then x, y = l + w / 2, b + h
    else x, y = l + w / 2, b end
    bar:ClearAllPoints()
    bar:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
    db.point, db.rel, db.x, db.y = point, "BOTTOMLEFT", x, y
end

-- Scale 0.3 - 2.0. The bar stays at the same screen position (positions are stored in the
-- scaled coordinate system and are converted).
local scalePending = false
function ns.ApplyScale()
    if InCombatLockdown() then scalePending = true return end -- the bar is protected in combat
    scalePending = false
    local new = db.scale or 1
    local old = bar:GetScale()
    if math.abs(new - old) < 0.001 then return end
    local cx, cy = bar:GetCenter()
    bar:SetScale(new)
    if cx and cy then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * old / new, cy * old / new)
        ns.ReAnchor()
    end
end

-- The handle shows while "Show anchor" is on, the mouse is over it or a drag runs; players
-- did not find it hidden (ruleset plan 2026-10-21-toggle-anchor). Alpha is not protected, so
-- this also runs in combat; the handle takes the mouse before login, when db is still nil.
function ns.ApplyHandle()
    local shown = (db and db.showAnchor) or handle:IsMouseOver() or handle.moving
    handle:SetAlpha(shown and 1 or 0)
end

-- Locked = red, unlocked = blue. The handle stays usable (to unlock and to open the settings).
function ns.ApplyLock()
    if db.locked then
        handleTex:SetColorTexture(0.9, 0.25, 0.2, 0.6)
    else
        handleTex:SetColorTexture(0.41, 0.8, 0.94, 0.6)
    end
    ns.ApplyHandle()
end

function ns.ToggleLock()
    db.locked = not db.locked
    ns.ApplyLock()
end

-- Hide in combat (secure state driver)
local combatPending = false
function ns.ApplyCombatHide()
    if InCombatLockdown() then combatPending = true return end
    combatPending = false
    if db.hideCombat then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
    end
end

local function ShowHandleTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("SimpleConjureBar")
    if db.locked then
        GameTooltip:AddLine(L.LOCKED, 1, 0.3, 0.3)
    else
        GameTooltip:AddLine(L.UNLOCKED, 0.4, 0.8, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.LEFTCLICK, L.MOVE, 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.MIDDLECLICK, L.SETTINGS, 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.RIGHTCLICK, db.locked and L.UNLOCK or L.LOCK, 0, 1, 0, 1, 1, 1)
    GameTooltip:Show()
end

handle:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    ShowHandleTooltip(self)
end)
handle:SetScript("OnLeave", function()
    ns.ApplyHandle()
    GameTooltip_Hide()
end)

handle:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" then
        -- The bar holds secure buttons, so it is protected in combat and cannot move
        if InCombatLockdown() then
            ns.Print(L.NOT_IN_COMBAT)
        elseif not db.locked then
            self.moving = true
            bar:StartMoving()
        end
    elseif btn == "RightButton" then
        ns.ToggleLock()
        handle:SetAlpha(1)
        ShowHandleTooltip(self)
    elseif btn == "MiddleButton" then
        ns.ToggleSettings()
    end
end)

-- Ends dragging. The bar contains secure buttons and is protected in combat, so
-- StopMovingOrSizing must not be called once the lockdown is active.
local function StopDrag()
    if not handle.moving then return end
    handle.moving = false
    if InCombatLockdown() then return end
    bar:StopMovingOrSizing()
    -- The automatic flyout direction depends on the screen half the bar now sits in
    ns.Rebuild()
    ns.ApplyHandle()
end
handle:SetScript("OnMouseUp", StopDrag)

-- PLAYER_REGEN_DISABLED fires right before the lockdown starts: a running drag is stopped
-- there while it is still allowed. PLAYER_REGEN_ENABLED applies changes made during combat.
local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:SetScript("OnEvent", function(_, event)
    local inCombat = (event == "PLAYER_REGEN_DISABLED")
    ns.ApplyCombatLook(inCombat)
    if inCombat then
        -- after the look: it hid the glows the key followed, without moving the key
        if db then ns.ArmorForCombat() end
        StopDrag()
    elseif db then
        if combatPending then ns.ApplyCombatHide() end
        if scalePending then ns.ApplyScale() end
    end
end)

-- Secure header for the flyout logic (works in combat)
local header = CreateFrame("Frame", "SimpleConjureBarHeader", UIParent, "SecureHandlerBaseTemplate")
ns.header = header

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- Secure button with its own action button look.
-- Deliberately WITHOUT ActionButtonTemplate: its scripts override the click handling of
-- SecureActionButtonTemplate in the Retail client.
local function CreateSecureButton(name, parent)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)

    -- Pixel-exact symmetric border: dark background, icon inset by 1 px.
    -- (Blizzard's UI-Quickslot2 texture is not exactly centered and overhangs the button.)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)

    b.icon = b:CreateTexture(nil, "BORDER")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Pushed and hover textures exactly on the icon
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    local pushed = b:GetPushedTexture()
    pushed:ClearAllPoints()
    pushed:SetAllPoints(b.icon)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local hl = b:GetHighlightTexture()
    hl:ClearAllPoints()
    hl:SetAllPoints(b.icon)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)

    -- Retail: secure buttons fire on key down or key up depending on the CVar
    -- "ActionButtonUseKeyDown". Both are registered; the client filters itself.
    b:RegisterForClicks("AnyUp", "AnyDown")
    return b
end

function ns.ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self.leftItem then
        GameTooltip:SetItemByID(self.leftItem)
    elseif self.spellId then
        GameTooltip:SetSpellByID(self.spellId)
    end
    -- The clicks in one order on every button - left, middle, right (Michel) - then an extra
    -- line such as the missing count. A field ending in Key holds a text's key, so the line
    -- follows a language switch.
    local left = self.hintLeftKey and L[self.hintLeftKey] or self.hintLeft
    local middle = self.hintMiddleKey and L[self.hintMiddleKey] or self.hintMiddle
    local right = self.hintKey and L[self.hintKey] or self.hint
    -- In combat only the lines of clicks that work there (ruleset plan 2026-10-25-combat-locks)
    local locked = InCombatLockdown() and self.lockedInCombat
    if locked then
        if locked.left then left = nil end
        if locked.middle then middle = nil end
        if locked.right then right = nil end
    end
    if left or middle or right then
        GameTooltip:AddLine(" ")
        if left then GameTooltip:AddLine(left, 0, 1, 0) end
        if middle then GameTooltip:AddLine(middle, 0, 1, 0) end
        if right then GameTooltip:AddLine(right, 0, 1, 0) end
        if self.hint2 then
            GameTooltip:AddLine(" ") -- set apart from the clicks (Michel)
            GameTooltip:AddLine(self.hint2, 0, 1, 0)
        end
    end
    GameTooltip:Show()
end
local ShowTooltip = ns.ShowTooltip

-- Demo mode: print what a click would do
local function DemoClick(b, btn)
    if btn == "MiddleButton" then return end -- trading has its own demo output
    if b.isGem then
        if btn == "RightButton" then
            DemoPrint(L.DEMO_CAST, ns.SpellName(b.conjureSpell) or "?")
        else
            DemoPrint(L.DEMO_CONSUME, b.leftItem and ItemName(b.leftItem) or L.ITEM)
        end
        return
    end
    if b.isBuff then
        -- the right click casts nothing: in a group it opens the settings (Intellect.lua)
        if btn ~= "RightButton" then DemoPrint(L.DEMO_CAST, ns.SpellName(b.leftSpell) or "?") end
        return
    end
    if b.key then
        if btn == "LeftButton" then
            DemoPrint(L.DEMO_CAST, ns.SpellName(b.spellId) or "?")
        end
    elseif btn == "RightButton" then
        local id = b.conjureSpell or b.spellId
        local rank = ""
        local list = b.spells
        for i, sid in ipairs(list) do
            if sid == id then rank = L.DEMO_RANK:format(#list - i + 1) end
        end
        DemoPrint(L.DEMO_CAST, (ns.SpellName(id) or "?") .. rank)
    else
        DemoPrint(L.DEMO_CONSUME, b.leftItem and ItemName(b.leftItem) or L.ITEM)
    end
end

local function OnMainClick(self, btn, down)
    -- Buttons are registered for down and up; report only once (on release)
    if IsDemo() and not down then DemoClick(self, btn) end
end

local function CreateMainButton(key)
    local b = CreateSecureButton("SimpleConjureBar_" .. key, bar)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:HookScript("OnClick", OnMainClick)
    ns.LogClicks(b, key)
    return b
end

---------------------------------------------------------------------------
-- Highlight: the modern client's proc glow (ruleset plan 2026-10-21-bar-alignment; the
-- "marching ants" before, whose names the code and the settings keep). It sits on its own
-- frame above the button and is desaturated, so its colour can be chosen freely; the client
-- plays its flipbook only while it is shown. ns.ApplyLook colours it and sets its speed.
---------------------------------------------------------------------------
local antsButtons = {}
local function AttachAnts(btn, colorKey, speedKey)
    local holder = CreateFrame("Frame", nil, btn)
    holder:SetAllPoints()
    holder:SetFrameLevel(btn:GetFrameLevel() + 2)

    local ants = holder:CreateTexture(nil, "OVERLAY")
    ants:SetAtlas(D.GLOW_ATLAS)
    ants:SetDesaturated(true)
    ants:SetPoint("CENTER")
    ants:SetSize(SIZE * D.GLOW_SCALE, SIZE * D.GLOW_SCALE)
    ants:Hide()

    local anim = ants:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local flip = anim:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(D.GLOW_ROWS)
    flip:SetFlipBookColumns(D.GLOW_COLUMNS)
    flip:SetFlipBookFrames(D.GLOW_FRAMES)

    btn.ants, btn.antsHolder, btn.antsAnim, btn.antsFlip = ants, holder, anim, flip
    btn.antsColorKey, btn.antsSpeedKey = colorKey, speedKey
    antsButtons[#antsButtons + 1] = btn
end

-- Shows or hides a button's highlight and starts or stops its animation; true when it changed
local function ShowAnts(btn, shown)
    if shown == btn.antsShown then return false end
    btn.antsShown = shown
    if shown then
        btn.ants:Show()
        btn.antsAnim:Play()
    else
        btn.ants:Hide()
        btn.antsAnim:Stop()
    end
    return true
end

function ns.SetAnts(btn, shown)
    -- The buff key casts what clears the first glowing button (Buttons.lua)
    if ShowAnts(btn, shown) and ns.UpdateBuffKey then ns.UpdateBuffKey() end
end

---------------------------------------------------------------------------
-- Main buttons
---------------------------------------------------------------------------
local intel = CreateMainButton("Intellect")
intel.isBuff = true
-- Intellect is locked in combat (saves mana, and targets cannot change under the lockdown):
-- the secure snippet drops every click while the player is in combat.
-- The armor buttons (always on yourself) stay usable in combat.
header:WrapScript(intel, "OnClick", [[ if PlayerInCombat() then return false end ]])
local ALL_LOCKED = { left = true, middle = true, right = true }
intel.lockedInCombat = ALL_LOCKED

-- Number: centered, big and bold (thick outline)
intel.count:ClearAllPoints()
intel.count:SetPoint("CENTER", intel, "CENTER", 0, 0)
ns.SetLatinFont(intel.count, NumberFontNormal, 20, "THICKOUTLINE") -- digits only
intel.count:SetJustifyH("CENTER")
AttachAnts(intel, "antsColor", "antsSpeed")
-- The number sits above the highlight
intel.count:SetParent(intel.antsHolder)
intel.count:SetDrawLayer("OVERLAY", 7)

local water = CreateMainButton("Water")
water.spells, water.items = D.WATER_SPELLS, D.WATER_ITEMS
local food = CreateMainButton("Food")
food.spells, food.items = D.FOOD_SPELLS, D.FOOD_ITEMS
-- Nobody eats, drinks or conjures them in a fight (Michel, 2026-10-25): every click is dropped
-- in combat, the trade too
for _, b in ipairs({ water, food }) do
    header:WrapScript(b, "OnClick", [[ if PlayerInCombat() then return false end ]])
    b.lockedInCombat = ALL_LOCKED
end

-- Mana Gem: highlight while no gem is in the bags; cooldown swipe
local gem = CreateMainButton("ManaGem")
gem.isGem = true
AttachAnts(gem, "gemAntsColor", "gemAntsSpeed")
gem.cooldown = CreateFrame("Cooldown", nil, gem, "CooldownFrameTemplate")
gem.cooldown:SetAllPoints(gem.icon)
-- Every gem costs more mana to conjure than it gives: its conjure is dropped in combat, a gem
-- is still used
header:WrapScript(gem, "OnClick", [[
    if button == "RightButton" and PlayerInCombat() then return false end
]])
gem.lockedInCombat = { right = true }

---------------------------------------------------------------------------
-- Flyout buttons (Armor, Teleport, Portal)
---------------------------------------------------------------------------
local flyouts = {}
ns.flyouts = flyouts

local function CreateFlyoutButton(key, listFn, hintKey, normalize, leftKey)
    local main = CreateMainButton(key)
    main.key = key
    main.hintKey = hintKey or "HINT_PICK"
    main.hintLeftKey = leftKey
    main.listFn, main.normalize = listFn, normalize

    local arrow = main:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    arrow:SetSize(14, 14)
    arrow:SetPoint("BOTTOM", main, "TOP", 0, -6)
    main.arrow = arrow

    -- Protected from the start: the right-click snippet reaches every flyout, and in combat
    -- the client refuses a handle to an unprotected frame ("Invalid frame handle"). A flyout
    -- without a known spell holds no secure button and would not be protected otherwise -
    -- the Portal menu before level 40 stopped every flyout opening in combat (in game,
    -- 2026-10-21).
    local tpl = API.BACKDROP_TPL and ("SecureFrameTemplate, " .. API.BACKDROP_TPL) or "SecureFrameTemplate"
    local fly = CreateFrame("Frame", "SimpleConjureBar_" .. key .. "Flyout", main, tpl)
    fly:SetPoint("BOTTOM", main, "TOP", 0, 6)
    fly:SetSize(SIZE + 2 * PAD, SIZE + 2 * PAD)
    if fly.SetBackdrop then
        fly:SetBackdrop(bar:GetBackdrop())
    end
    fly:Hide()
    fly.buttons = {}
    main.fly = fly
    flyouts[key] = fly

    header:SetFrameRef("main_" .. key, main)
    header:SetFrameRef("fly_" .. key, fly)

    -- Right click: toggle this menu (closing the others) and cancel the action. An open menu
    -- closes by itself once the mouse has left it and its button for the header's "autohide"
    -- seconds - a secure hide, so also in combat; every hidden menu drops that registration.
    -- gsub returns two values; the extra parentheses pass on the string only.
    header:WrapScript(main, "OnClick", (([[
        if button == "RightButton" then
            -- Toggle on release only, otherwise it opens and closes again right away
            if down then return false end
            local fly = owner:GetFrameRef("fly_KEY")
            for _, k in pairs(newtable("Armor", "Teleport", "Portal")) do
                local other = owner:GetFrameRef("fly_" .. k)
                if other and other ~= fly then
                    other:Hide()
                    other:UnregisterAutoHide()
                end
            end
            if fly:IsShown() then
                fly:Hide()
                fly:UnregisterAutoHide()
            else
                fly:Show()
                fly:RegisterAutoHide(owner:GetAttribute("autohide"))
                fly:AddToAutoHide(self)
            end
            return false
        end
    ]]):gsub("KEY", key)))

    return main
end

local armor = CreateFlyoutButton("Armor", ns.KnownArmor, "HINT_PICK_ARMOR", ns.NormalizeArmor, "HINT_CAST_ARMOR")
armor.isArmor = true
AttachAnts(armor, "armorAntsColor", "armorAntsSpeed")

-- Short label centered at the bottom of the icon
local function AddArmorLabel(btn, parent)
    -- Blizzard font object with outline (all alphabets, e.g. Chinese armor names)
    btn.label = (parent or btn):CreateFontString(nil, "OVERLAY",
        ns.FontObject("GameFontHighlightSmallOutline", "GameFontHighlightSmall"))
    btn.label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    btn.label:SetDrawLayer("OVERLAY", 7)
end
AddArmorLabel(armor, armor.antsHolder) -- above the highlight

local tele   = CreateFlyoutButton("Teleport", function() return ns.KnownTravel("tele") end, nil, nil, "HINT_TELEPORT")
local portal = CreateFlyoutButton("Portal", function() return ns.KnownTravel("portal") end, nil, nil, "HINT_PORTAL")
tele.rune, portal.rune = D.ITEM_RUNE_TELE, D.ITEM_RUNE_PORTAL
for _, b in ipairs({ tele, portal }) do
    ns.SetLatinFont(b.count, NumberFontNormal, 14, "OUTLINE") -- digits only
    b.count:SetDrawLayer("OVERLAY", 7)
    -- The game refuses teleports and portals in combat (in game, 2026-10-21): the left click
    -- is dropped then, as Intellect's; the right click still opens the menu to choose
    header:WrapScript(b, "OnClick", [[
        if button == "LeftButton" and PlayerInCombat() then return false end
    ]])
    b.lockedInCombat = { left = true }
end

ns.buttons = {
    Armor = armor, Intellect = intel, ManaGem = gem, Water = water,
    Food = food, Teleport = tele, Portal = portal,
}

---------------------------------------------------------------------------
-- "Cast next buff" key (Bindings.xml): a hidden secure button holding what clears the first
-- glowing button of the bar. ns.UpdateBuffKey (Buttons.lua) writes it out of combat.
---------------------------------------------------------------------------
local buffKey = CreateFrame("Button", "SimpleConjureBarBuffAll", UIParent, "SecureActionButtonTemplate")
buffKey:Hide()
buffKey:RegisterForClicks("AnyUp", "AnyDown")
ns.buffKey = buffKey
header:SetFrameRef("buffkey", buffKey)
-- In combat the key casts the armor only: Intellect and the gem's conjure are locked there, as
-- on their buttons; without an armor on the bar it keeps them (Buttons.lua ArmorForCombat)
header:WrapScript(buffKey, "OnClick", [[
    if PlayerInCombat() and self:GetAttribute("scbsource") ~= "Armor" then return false end
]])
buffKey:HookScript("OnClick", function(self, _, down)
    if IsDemo() and not down and self.demoSpell then
        DemoPrint(L.DEMO_CAST, ns.SpellName(self.demoSpell) or "?")
    end
end)
ns.LogClicks(buffKey, buffKey:GetName())

-- Flyout child buttons are created on demand
function ns.GetFlyoutChild(main, i)
    local fly = main.fly
    local c = fly.buttons[i]
    if c then return c end

    -- An icon has no "type": a click on it chooses and casts nothing; the main button casts
    -- (Michel, 2026-10-21, as in SmartBlessingBar)
    c = CreateSecureButton(fly:GetName() .. i, fly)
    c:SetScript("OnEnter", ShowTooltip)
    c:SetScript("OnLeave", GameTooltip_Hide)
    ns.LogClicks(c, c:GetName())

    -- A left click chooses: copy the spell to the main button and close the menu (secure, works
    -- in combat). An armor chosen also reaches the buff key while it holds Armor's click; the
    -- line is in the Armor menu's snippet only, so a teleport never reaches the key.
    local toKey = main.isArmor and [[
        local key = owner:GetFrameRef("buffkey")
        if key:GetAttribute("scbsource") == "Armor" then key:SetAttribute("spell1", self:GetAttribute("spell")) end
    ]] or ""
    header:WrapScript(c, "OnClick", [[
        if button ~= "LeftButton" then return false end
        return nil, "done"
    ]], toKey .. (([[
        local main = owner:GetFrameRef("main_KEY")
        main:SetAttribute("spell1", self:GetAttribute("spell"))
        if not down then
            local fly = self:GetParent()
            fly:Hide()
            fly:UnregisterAutoHide()
        end
    ]]):gsub("KEY", main.key)))

    if main.isArmor then AddArmorLabel(c) end

    -- Remember the choice and update the main button icon
    c:HookScript("OnClick", function(self, button, down)
        if button ~= "LeftButton" then return end
        db.last[main.key] = self.spellId
        main.spellId = self.spellId
        main.icon:SetTexture(GetSpellTex(self.spellId))
        if main.label then main.label:SetText(ns.ArmorShortName(self.spellId)) end
        if IsDemo() and not down then
            DemoPrint(main.isArmor and L.DEMO_CAST or L.DEMO_PICKED, ns.SpellName(self.spellId) or "?")
        end
        ns.UpdateBuffKey()
    end)

    fly.buttons[i] = c
    return c
end

---------------------------------------------------------------------------
-- Look: background color, border and highlight colors
---------------------------------------------------------------------------
local demoLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
demoLabel:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 4, 1)
ns.SetL(demoLabel, "DEMO_LABEL")
demoLabel:SetTextColor(1, 0.6, 0.2)
demoLabel:Hide()

local BACKDROP_FRAMES = { bar, flyouts.Armor, flyouts.Teleport, flyouts.Portal }

function ns.ApplyLook()
    local c = db.bg
    local borderAlpha = db.showBorder and 0.8 or 0
    for _, f in ipairs(BACKDROP_FRAMES) do
        if f.SetBackdropColor then
            f:SetBackdropColor(c.r, c.g, c.b, c.a)
            -- Demo mode deliberately uses the live look; it is only marked by the DEMO label
            f:SetBackdropBorderColor(0.4, 0.4, 0.4, borderAlpha)
        end
    end
    if IsDemo() then demoLabel:Show() else demoLabel:Hide() end

    local cc = db.countColor
    intel.count:SetTextColor(cc.r, cc.g, cc.b, cc.a)
    for _, b in ipairs(antsButtons) do
        local a = db[b.antsColorKey]
        b.ants:SetVertexColor(a.r, a.g, a.b, a.a)
        b.antsFlip:SetDuration(D.GLOW_DURATIONS[db[b.antsSpeedKey]])
    end

    local lc = db.armorLabelColor
    armor.label:SetTextColor(lc.r, lc.g, lc.b, lc.a)
    for _, child in ipairs(armor.fly.buttons) do
        if child.label then child.label:SetTextColor(lc.r, lc.g, lc.b, lc.a) end
    end
end

-- Intellect, water, food, Teleport and Portal are greyed out in combat: their clicks are
-- dropped then. Intellect's count and glow go too, and the gem's glow - its conjure is locked.
-- Hiding a glow leaves the key alone: ArmorForCombat decides from what it held. Combat's end
-- shows them again (UpdateBuffState, UpdateCounts).
local COMBAT_LOCKED = { intel, water, food, tele, portal }
local GREY = 0.5
function ns.ApplyCombatLook(inCombat)
    for _, b in ipairs(COMBAT_LOCKED) do
        b.icon:SetDesaturated(inCombat)
        b.icon:SetAlpha(inCombat and 0.6 or 1)
    end
    local c = inCombat and GREY or 1
    for _, b in ipairs({ water, food }) do b.count:SetTextColor(c, c, c, 1) end
    if inCombat then
        intel.count:SetText("")
        ShowAnts(intel, false)
        ShowAnts(gem, false)
    end
end
