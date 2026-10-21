-- SimpleConjureBar - settings pages
-- Tabs: General, Tracking, Supplies, Order. Built with the widgets from Settings.lua.

local _, ns = ...
if not ns.enabled then return end

local D, L, API, UI = ns.D, ns.L, ns.API, ns.UI
local INSET, Place = UI.INSET, UI.Place
local refreshers, measures, stretchers = UI.refreshers, UI.measures, UI.stretchers

local db
ns.OnDBReady(function(d) db = d end)

local function Rebuild() ns.Rebuild() end

---------------------------------------------------------------------------
-- Tab 1: General
---------------------------------------------------------------------------
local general = UI.NewPage("TAB_GENERAL")
-- Language: "Automatic" always follows the client language, otherwise a fixed choice
-- (saved account-wide)
do
    local opts = { { value = "auto", text = function()
        return L.LANG_AUTO:format(ns.LOCALE_NAMES[ns.clientLocale] or ns.clientLocale)
    end } }
    for _, code in ipairs(ns.LOCALE_ORDER) do
        opts[#opts + 1] = { value = code, text = function() return ns.LOCALE_NAMES[code] end }
    end
    UI.AddDropdown("OPT_LANGUAGE", opts, function()
        return SimpleConjureBarGlobalDB.language or "auto"
    end, function(v)
        SimpleConjureBarGlobalDB.language = (v ~= "auto") and v or nil
        ns.ApplyLanguage(v == "auto" and ns.clientLocale or v)
    end)
end
UI.AddCheckRow({
    { label = "OPT_HIDE_COMBAT",  key = "hideCombat",  onChange = function() ns.ApplyCombatHide() end },
    { label = "OPT_HIDE_MINIMAP", key = "hideMinimap", onChange = function() ns.ApplyMinimapButton() end },
})
UI.AddSeparator()

-- Scale: slider in 0.1 steps or number input (0.05 steps)
do
    local ROW = 40
    local row = CreateFrame("Frame", nil, general)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", INSET, Place(ROW, 6))

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 0, -4)
    ns.SetL(label, "OPT_SCALE")

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(44, 20)
    box:SetPoint("TOPRIGHT", 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(4)
    box:SetJustifyH("CENTER")

    local slider = UI.MakeSlider(row)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -10)
    slider:SetMinMaxValues(D.SCALE_MIN, D.SCALE_MAX)
    slider:SetValueStep(0.05) -- fine step, so typed 0.05 values stay where they are

    local function Round(v, step) return math.floor(v / step + 0.5) * step end
    local function Format(v) return (("%.2f"):format(v):gsub("0$", "")) end -- 1.00 -> 1.0, 1.05 stays

    local updating = false
    local function SetScaleValue(v, fromSlider)
        v = math.max(D.SCALE_MIN, math.min(D.SCALE_MAX, v))
        v = Round(v, fromSlider and 0.1 or 0.05)
        db.scale = tonumber(("%.2f"):format(v))
        updating = true
        slider:SetValue(db.scale)
        updating = false
        box:SetText(Format(db.scale))
        ns.ApplyScale()
    end

    slider:SetScript("OnValueChanged", function(_, v)
        if updating then return end
        SetScaleValue(v, true) -- dragging snaps to 0.1 steps
    end)
    slider:SetScript("OnMouseWheel", function(_, delta)
        SetScaleValue((db.scale or 1) + delta * 0.1, true)
    end)

    local function ApplyBox(self)
        local text = (self:GetText() or ""):gsub(",", ".") -- allow a comma as decimal separator
        local v = tonumber(text)
        -- v == v rejects NaN
        if v and v == v then SetScaleValue(v, false) else self:SetText(Format(db.scale or 1)) end
        self:ClearFocus()
    end
    box:SetScript("OnEnterPressed", ApplyBox)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(Format(db.scale or 1))
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self) self:SetText(Format(db.scale or 1)) end)

    refreshers[#refreshers + 1] = function()
        updating = true
        slider:SetValue(db.scale or 1)
        updating = false
        box:SetText(Format(db.scale or 1))
    end
    measures[#measures + 1] = function() return label:GetStringWidth() + 16 + 44 end
    stretchers[#stretchers + 1] = function(w)
        row:SetWidth(w)
        slider:SetWidth(w - 4)
    end
end

UI.AddCheck("OPT_BORDER", "showBorder", function() ns.ApplyLook() end)
UI.AddSwatch("OPT_BG", "bg", 8)
UI.AddSeparator()

-- Orientation and growth direction (anchor point of the bar)
local RefreshDirection, RefreshFlyDir
UI.AddDropdown("OPT_LAYOUT", {
    { value = false, text = function() return L.HORIZONTAL end },
    { value = true,  text = function() return L.VERTICAL end },
}, function() return db.vertical end, function(v)
    db.vertical = v
    -- direction texts (right/left or down/up), and the flyout sides they name
    if RefreshDirection then RefreshDirection() end
    if RefreshFlyDir then RefreshFlyDir() end
    Rebuild()
end)
RefreshDirection = UI.AddDropdown("OPT_DIRECTION", {
    { value = false, text = function() return (db and db.vertical) and L.DIR_DOWN or L.DIR_RIGHT end },
    { value = true,  text = function() return (db and db.vertical) and L.DIR_UP or L.DIR_LEFT end },
}, function() return db.growRev end, function(v)
    db.growRev = v
    Rebuild()
end)

-- Flyout direction: automatic by screen half, or a side named by the orientation
-- (ruleset plan 2026-10-21-bar-alignment), and how long an open flyout waits for the mouse
RefreshFlyDir = UI.AddDropdown("OPT_FLYDIR", {
    { value = "AUTO",   text = function() return L.FLYDIR_AUTO end },
    { value = "FIRST",  text = function() return (db and db.vertical) and L.DIR_RIGHT or L.DIR_UP end },
    { value = "SECOND", text = function() return (db and db.vertical) and L.DIR_LEFT or L.DIR_DOWN end },
}, function() return db.flyoutDir end, function(v)
    db.flyoutDir = v
    Rebuild()
end)
UI.AddIntSlider("OPT_AUTOCLOSE", "flyoutAutoClose", D.AUTOCLOSE_MIN, D.AUTOCLOSE_MAX, function(v)
    return v == D.VALUE_DEFAULTS.flyoutAutoClose and (v .. " (" .. L.DEFAULT .. ")") or tostring(v)
end, nil, function() ns.ApplyAutoClose() end)

UI.AddSeparator()

UI.AddCheck("OPT_DEMO", "demo", function()
    Rebuild()
    ns.ApplyLook()
end)

-- Bottom row: "Report bug" left, "Reload UI" right (own translations, so they follow the language)
do
    local reload = UI.AddButton(general, "RELOAD_UI", function() ReloadUI() end)
    reload:SetPoint("BOTTOMRIGHT", general, "BOTTOMRIGHT", -INSET, INSET - 4)
    local bug = UI.AddButton(general, "BTN_REPORT_BUG", function() ns.OpenBugReport() end)
    bug:SetPoint("BOTTOMLEFT", general, "BOTTOMLEFT", INSET, INSET - 4)
    UI.measures[#UI.measures + 1] = function() return bug:GetWidth() + 12 + reload:GetWidth() end
    -- Reserve the space, so the button never overlaps the last element
    Place(22, 8)
end

---------------------------------------------------------------------------
-- Tab 2: Tracking (sections in the default bar order: Armor, Buff, Mana Gem)
---------------------------------------------------------------------------
UI.NewPage("TAB_TRACKING")

UI.AddHeader("TRACK_ARMOR", 6)
UI.AddToggleColorRow("OPT_SHOW_BUTTON", "showArmor", Rebuild, {
    { label = "LBL_HIGHLIGHT", key = "armorAntsColor" },
    { label = "LBL_TEXT",      key = "armorLabelColor" },
})
UI.AddSpeedSlider("armorAntsSpeed")
UI.AddSeparator()

UI.AddHeader("TRACK_BUFF", 6)
UI.AddToggleColorRow("OPT_SHOW_BUTTON", "showIntellect", Rebuild, {
    { label = "LBL_HIGHLIGHT", key = "antsColor" },
    { label = "LBL_TEXT",      key = "countColor" },
})
UI.AddSpeedSlider("antsSpeed")
UI.AddSeparator()

UI.AddHeader("MANA_GEM", 6)
UI.AddToggleColorRow("OPT_SHOW_BUTTON", "showGem", Rebuild, {
    { label = "LBL_HIGHLIGHT", key = "gemAntsColor" },
})
UI.AddSpeedSlider("gemAntsSpeed")

---------------------------------------------------------------------------
-- Tab 3: Supplies (reagent tracking and auto-buy)
---------------------------------------------------------------------------
UI.NewPage("TAB_SUPPLIES")

-- Reagent tracking: rune count on Teleport/Portal
UI.AddHeader("REAGENT_TRACKING", 6)
UI.AddNumberSlider({
    label = "OPT_RUNE_WARN", min = 0, max = D.RUNE_WARN_MAX,
    get = function() return db.runeWarn end,
    set = function(v) db.runeWarn = v end,
    gap = 6,
})
UI.AddToggleColorRow(nil, nil, nil, {
    { label = "LBL_WARNING", key = "runeWarnColor" },
    { label = "LBL_EMPTY",   key = "runeZeroColor" },
})
UI.AddSeparator()

UI.AddHeader("AUTOBUY_HEADER", 6)
local amountRows = {}
local function ApplyAutoBuyState()
    for _, row in ipairs(amountRows) do row:SetAlpha(db.autoBuy and 1 or 0.4) end
end
UI.AddCheck("OPT_AUTOBUY", "autoBuy", ApplyAutoBuyState)
refreshers[#refreshers + 1] = ApplyAutoBuyState
UI.AddNumberSlider({
    label = "OPT_GOLD_RESERVE", min = 0, max = D.GOLD_RESERVE_MAX,
    get = function() return db.goldReserve end,
    set = function(v) db.goldReserve = v end,
    gap = 6, rows = amountRows,
})
UI.AddNote("OPT_AMOUNTS", 8)

for _, r in ipairs(D.REAGENTS) do
    UI.AddNumberSlider({
        label = function() return ns.LocalName(API.ItemName(r.id), r.nameKey) end,
        icon = function() return API.ItemIcon(r.id) or "Interface\\Icons\\INV_Misc_QuestionMark" end,
        min = 0, max = D.AMOUNT_MAX,
        get = function() return db.amounts[r.id] or 0 end,
        set = function(v) db.amounts[r.id] = v end,
        gap = 4, rows = amountRows,
    })
end

---------------------------------------------------------------------------
-- Tab 4: button order (drag and drop)
---------------------------------------------------------------------------
local orderPage = UI.NewPage("TAB_ORDER")

local function FirstTravel(key)
    local list = D.TRAVEL[UnitFactionGroup("player")] or D.TRAVEL.Horde
    return list[1][key]
end

-- Name and icon (spell ID) per button; the lowest rank is used for the icon
local ORDER_INFO = {
    Armor     = { name = function() return L.ARMOR end,        icon = D.ARMOR_BUFF_IDS[1] },
    Intellect = { name = function() return ns.LocalName(ns.SpellName(D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT") end,
                  icon = D.SPELL_ARCANE_INTELLECT },
    ManaGem   = { name = function() return L.MANA_GEM end,     icon = D.MANA_GEMS[#D.MANA_GEMS].spell },
    Water     = { name = function() return L.BTN_WATER end,    icon = D.WATER_SPELLS[#D.WATER_SPELLS] },
    Food      = { name = function() return L.BTN_FOOD end,     icon = D.FOOD_SPELLS[#D.FOOD_SPELLS] },
    Teleport  = { name = function() return L.BTN_TELEPORT end, icon = FirstTravel("tele") },
    Portal    = { name = function() return L.BTN_PORTAL end,   icon = FirstTravel("portal") },
}

do
    UI.AddNote("ORDER_HINT", 10)

    local ROW, ROW_GAP = 26, 2
    local rows = {}
    local RefreshOrder
    local drag -- { key, index } while dragging

    -- Row under the mouse cursor (1..n), no matter where exactly the row is grabbed
    local function SlotUnderCursor()
        local top = rows[1]:GetTop()
        if not top then return drag.index end
        local _, cy = GetCursorPosition()
        cy = cy / rows[1]:GetEffectiveScale()
        local slot = math.floor((top - cy) / (ROW + ROW_GAP)) + 1
        return math.max(1, math.min(#rows, slot))
    end

    local function StopOrderDrag()
        if not drag then return end
        drag = nil
        orderPage:SetScript("OnUpdate", nil)
        RefreshOrder()
        Rebuild() -- rebuild the bar only after the row was dropped
    end

    local function OnDragUpdate()
        -- Safety net: mouse button released outside the window
        if not IsMouseButtonDown("LeftButton") then StopOrderDrag() return end
        local slot = SlotUnderCursor()
        if slot ~= drag.index then
            -- Move the entry live to its new position
            table.remove(db.order, drag.index)
            table.insert(db.order, slot, drag.key)
            drag.index = slot
            RefreshOrder()
        end
    end

    local function StartOrderDrag(index)
        drag = { key = db.order[index], index = index }
        RefreshOrder()
        orderPage:SetScript("OnUpdate", OnDragUpdate)
    end

    for i = 1, #D.DEFAULT_ORDER do
        local row = CreateFrame("Frame", nil, orderPage)
        row:SetHeight(ROW)
        row:SetPoint("TOPLEFT", INSET, Place(ROW, ROW_GAP))
        row:EnableMouse(true)

        -- Background: subtle on hover, gold while dragging
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0)

        row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.num:SetPoint("LEFT", 4, 0)
        row.num:SetWidth(16)
        row.num:SetJustifyH("RIGHT")
        row.num:SetText(i .. ".")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", row.num, "RIGHT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)

        -- Burger grip (three lines) on the right shows that the row can be dragged
        row.grip = {}
        for k = 1, 3 do
            local line = row:CreateTexture(nil, "ARTWORK")
            line:SetSize(14, 2)
            line:SetPoint("RIGHT", row, "RIGHT", -6, (2 - k) * 5)
            line:SetColorTexture(0.6, 0.6, 0.6, 1)
            row.grip[k] = line
        end

        function row.SetGripColor(r, g, b)
            for _, line in ipairs(row.grip) do line:SetColorTexture(r, g, b, 1) end
        end

        row:SetScript("OnEnter", function(self)
            if drag then return end
            self.bg:SetColorTexture(1, 1, 1, 0.06)
            self.SetGripColor(1, 0.82, 0)
        end)
        row:SetScript("OnLeave", function(self)
            if drag then return end
            self.bg:SetColorTexture(1, 1, 1, 0)
            self.SetGripColor(0.6, 0.6, 0.6)
        end)
        row:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then StartOrderDrag(i) end
        end)
        row:SetScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" then StopOrderDrag() end
        end)

        rows[i] = row
        measures[#measures + 1] = function() return 4 + 16 + 6 + 22 + 8 + row.label:GetStringWidth() + 16 + 20 end
        stretchers[#stretchers + 1] = function(w) row:SetWidth(w) end
    end

    RefreshOrder = function()
        for i, row in ipairs(rows) do
            local info = ORDER_INFO[db.order[i]]
            row.label:SetText(info.name())
            row.icon:SetTexture(API.GetSpellTex(info.icon))
            -- Highlight the dragged row
            if drag and drag.index == i then
                row.bg:SetColorTexture(1, 0.82, 0, 0.18)
                row.SetGripColor(1, 0.82, 0)
            elseif not row:IsMouseOver() or drag then
                row.bg:SetColorTexture(1, 1, 1, 0)
                row.SetGripColor(0.6, 0.6, 0.6)
            end
        end
    end
    refreshers[#refreshers + 1] = RefreshOrder
    orderPage:SetScript("OnHide", StopOrderDrag)

    -- Restore the default order
    local reset = UI.AddButton(orderPage, "DEFAULT", function()
        db.order = {}
        for k, v in ipairs(D.DEFAULT_ORDER) do db.order[k] = v end
        RefreshOrder()
        Rebuild()
    end)
    reset:SetPoint("TOPLEFT", INSET, Place(22, 6) - 6)
end

---------------------------------------------------------------------------
-- Tab 5: Macros
---------------------------------------------------------------------------
local macroPage = UI.NewPage("TAB_MACROS")

-- A spell's name in the addon's language (ns.LocalName), as a function for ns.SetL
local function SpellLabel(spellId)
    return ns.LocalName(ns.SpellName(spellId), D.SPELL_NAME_KEYS[spellId])
end

-- Polymorph: the raid marker, then one button - laid out like the stopcasting section
UI.AddHeader(function() return SpellLabel(D.SPELL_POLYMORPH) end, 6)
do
    -- Raid marker used by the macro (applied when the macro is created or updated)
    local opts = {}
    for i = 1, 8 do
        opts[i] = { value = i, text = function()
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":14|t "
                .. ns.LocalName(_G["RAID_TARGET_" .. i], "MARKER_" .. i)
        end }
    end
    UI.AddDropdown("OPT_MARKER", opts, function() return db.macroMarker end,
        function(v) db.macroMarker = v end)
    local create = UI.AddButton(macroPage, "BTN_CREATE_MACRO", function() ns.CreatePolymorphMacro() end)
    create:SetPoint("TOPLEFT", INSET, Place(22, 6))
    UI.AddNote("MACRO_HELP", 8, 3) -- three lines
end

-- Ice Block: one button
UI.AddSeparator()
UI.AddHeader(function() return SpellLabel(D.SPELL_ICE_BLOCK) end, 6)
do
    local create = UI.AddButton(macroPage, "BTN_CREATE_MACRO", function() ns.CreateIceBlockMacro() end)
    create:SetPoint("TOPLEFT", INSET, Place(22, 6))
    UI.AddNote(function() return L.MACRO_ICEBLOCK_HELP:format(SpellLabel(D.SPELL_ICE_BLOCK)) end, 8)
end

-- Stopcasting: the chosen spell, then one button for its macro
UI.AddSeparator()
UI.AddHeader("MACRO_STOPCAST_HEADER", 6)
do
    local opts = {}
    for i, id in ipairs(D.STOPCAST_SPELLS) do
        opts[i] = { value = id, text = function() return SpellLabel(id) end }
    end
    UI.AddDropdown("OPT_STOPCAST_SPELL", opts, function() return db.macroStopcast end,
        function(v) db.macroStopcast = v end)
    local create = UI.AddButton(macroPage, "BTN_CREATE_MACRO", function() ns.CreateStopcastMacro() end)
    create:SetPoint("TOPLEFT", INSET, Place(22, 6))
    UI.AddNote(function() return L.MACRO_STOPCAST_HELP:format(SpellLabel(D.SPELL_COUNTERSPELL)) end, 8, 2)
end

-- "Show macro" in the bottom right corner, as "Reload UI" on the General tab
do
    local show = UI.AddButton(macroPage, "BTN_SHOW_MACRO", function() ns.ShowMacroWindow() end)
    show:SetPoint("BOTTOMRIGHT", macroPage, "BOTTOMRIGHT", -INSET, INSET - 4)
    -- Reserve the space, so the button never overlaps the last element
    Place(22, 8)
end

UI.CreateTabs()
