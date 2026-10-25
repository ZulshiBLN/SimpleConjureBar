-- SimpleConjureBar - settings window framework
-- The window, its layout system and the reusable widgets. The pages themselves are built in
-- SettingsPages.lua with the helpers exported as ns.UI.
--
-- Layout system: every widget registers
--   refreshers - load the values from the settings into the widget (on show and language change)
--   measures   - return the content width the widget needs (texts differ per language)
--   stretchers - fit the widget to the final content width
-- so the window always fits its content in every language.

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local SetL, Print = ns.SetL, ns.Print

local db
ns.OnDBReady(function(d) db = d end)

local UI = {}
ns.UI = UI

---------------------------------------------------------------------------
-- Window background, invisible to solid (ruleset plan 2026-10-22-window-opacity). The dialog
-- texture lets the game show through and can never become solid on its own: it fades out
-- below today's value, and a black layer beneath it fills in above. At today's value it is
-- the window as it always was. Frame edge, texts and controls are not touched.
---------------------------------------------------------------------------
-- Called right after SetBackdrop; a client without BackdropTemplate has no backdrop to change
function ns.AddOpacityLayer(window)
    if not window.Center then return end
    local layer = window:CreateTexture(nil, "BACKGROUND", nil, -8)
    layer:SetColorTexture(0, 0, 0, 1)
    layer:SetPoint("TOPLEFT", 11, -12)     -- the backdrop's insets
    layer:SetPoint("BOTTOMRIGHT", -12, 11)
    window.Center:SetDrawLayer("BACKGROUND", -7) -- the dialog texture stays above it
    window.opacityLayer = layer
end

function ns.ApplyWindowOpacity(window)
    if not (db and window.opacityLayer) then return end
    local o, d = db.windowOpacity / 100, D.WINDOW_OPACITY_TODAY / 100
    window:SetBackdropColor(1, 1, 1, math.min(1, o / d))
    window.opacityLayer:SetAlpha(math.max(0, (o - d) / (1 - d)))
end

-- Both windows at once, for the slider; the report applies again whenever it shows
function ns.ApplyWindowOpacities()
    ns.ApplyWindowOpacity(UI.window)
    ns.ApplyReportOpacity()
end

local settings = CreateFrame("Frame", "SimpleConjureBarSettings", UIParent, API.BACKDROP_TPL)
UI.window = settings
settings:SetSize(300, 290)
settings:SetPoint("CENTER")
settings:SetFrameStrata("DIALOG")
settings:SetMovable(true)
settings:EnableMouse(true)
settings:RegisterForDrag("LeftButton")
-- placers run when the window moved or changed size: the docked bug report keeps itself on the
-- screen (ruleset plan 2026-10-25-chat-and-docked-report)
local placers = {}
UI.placers = placers
function UI.Placed() for _, f in ipairs(placers) do f() end end
settings:SetScript("OnDragStart", settings.StartMoving)
settings:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    UI.Placed()
end)
settings:SetClampedToScreen(true)
settings:Hide()
if settings.SetBackdrop then
    settings:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    ns.AddOpacityLayer(settings)
end
tinsert(UISpecialFrames, "SimpleConjureBarSettings") -- closes with Escape

-- The dialog border is about 12 px wide, plus 10 px space to the content
local INSET = 22
local MIN_W = 240
local TOP_Y = -84 -- below the title and the tabs
UI.INSET = INSET

local refreshers, measures, stretchers = {}, {}, {}
UI.refreshers, UI.measures, UI.stretchers = refreshers, measures, stretchers

---------------------------------------------------------------------------
-- Pages (tabs): every page has its own placement cursor
---------------------------------------------------------------------------
local pages, page = {}, nil

function UI.NewPage(titleKey)
    local pg = CreateFrame("Frame", nil, settings)
    pg:SetPoint("TOPLEFT")
    pg:SetPoint("BOTTOMRIGHT")
    pg:Hide()
    pg.cursorY, pg.titleKey = TOP_Y, titleKey
    pages[#pages + 1] = pg
    page = pg
    return pg
end
function UI.CurrentPage() return page end

-- Reserves vertical space on the current page and returns its top offset
function UI.Place(height, gap)
    local y = page.cursorY
    page.cursorY = page.cursorY - height - (gap or 6)
    return y
end
local Place = UI.Place

---------------------------------------------------------------------------
-- Title with version, close button
---------------------------------------------------------------------------
local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetText("SimpleConjureBar")

-- Version slightly smaller and white right after the title
local titleVersion = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
titleVersion:SetText("v" .. ns.VERSION)
titleVersion:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)

-- Center title and version together
local function PlaceTitle()
    local shift = (titleVersion:GetStringWidth() + 6) / 2
    title:ClearAllPoints()
    title:SetPoint("TOP", settings, "TOP", -math.floor(shift), -18)
end
PlaceTitle()
-- Leave room for the close button on both sides of the centered title
measures[#measures + 1] = function()
    PlaceTitle()
    return title:GetStringWidth() + 6 + titleVersion:GetStringWidth() + 2 * 34
end

local close = CreateFrame("Button", nil, settings, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- Check box with label, bound to a boolean setting. Shared by all check box widgets.
local function CreateCheck(parent, labelKey, key, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    SetL(text, labelKey)
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(db[key]) end
    return cb, text
end

-- Single check box in its own row; indent moves it in by that many check box widths (an option
-- that belongs to the box above it). Returns the check box.
function UI.AddCheck(labelKey, key, onChange, indent)
    local cb, text = CreateCheck(page, labelKey, key, onChange)
    local x = INSET - 3 + (indent or 0) * 26
    cb:SetPoint("TOPLEFT", x, Place(26, 2))
    measures[#measures + 1] = function() return x - INSET + 26 + 4 + text:GetStringWidth() end
    return cb
end

-- Several check boxes next to each other. items = { { label =, key =, onChange = }, ... }
function UI.AddCheckRow(items)
    local ROW, SPACING = 26, 24
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", INSET - 3, Place(ROW, 2))
    local parts = {}
    for _, it in ipairs(items) do
        local cb, text = CreateCheck(row, it.label, it.key, it.onChange)
        parts[#parts + 1] = { cb = cb, text = text }
    end
    local function Arrange()
        local x = 0
        for _, p in ipairs(parts) do
            p.cb:ClearAllPoints()
            p.cb:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + 26 + 4 + p.text:GetStringWidth() + SPACING
        end
        row.needW = x - SPACING - 3
    end
    refreshers[#refreshers + 1] = Arrange
    measures[#measures + 1] = function() return row.needW or 0 end
    stretchers[#stretchers + 1] = function(w) row:SetWidth(w + 3) end
end

-- Section header: a bit larger than body text with more space below. Uses a Blizzard font
-- object (all alphabets); the window title stays the largest text.
local HEADER_SIZE = 14
local HEADER_FONT = ns.FontObject("GameFontNormalMed3", "GameFontNormalMed2", "GameFontNormal")
function UI.AddHeader(labelKey, gap)
    local h = page:CreateFontString(nil, "OVERLAY", HEADER_FONT)
    h:SetTextColor(1, 0.82, 0) -- Blizzard gold
    h:SetPoint("TOPLEFT", INSET, Place(HEADER_SIZE + 4, (gap or 8) + 4))
    SetL(h, labelKey)
    measures[#measures + 1] = function() return h:GetStringWidth() end
end

-- Small explanatory text in its own row. lines: number of lines (texts use "\n" breaks)
function UI.AddNote(labelKey, gap, lines)
    local t = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    t:SetPoint("TOPLEFT", INSET, Place(12 * (lines or 1) + 2 * ((lines or 1) - 1), gap or 8))
    SetL(t, labelKey)
    measures[#measures + 1] = function() return t:GetStringWidth() end
    return t
end

-- Plain slider without template (works on Classic and Retail clients)
function UI.MakeSlider(parent)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetHeight(12)
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.25, 1)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 0.82, 0, 1) -- WoW gold
    slider:SetThumbTexture(thumb)
    slider:EnableMouseWheel(true)
    return slider
end
local MakeSlider = UI.MakeSlider

-- Integer slider with label and value text. fmt(v) returns the displayed value.
function UI.AddIntSlider(labelKey, key, minV, maxV, fmt, gap, onChange)
    local ROW = 36
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", INSET, Place(ROW, gap or 14))

    local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOPLEFT", 0, 0)
    SetL(t, labelKey)
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPRIGHT", 0, 0)

    local slider = MakeSlider(row)
    slider:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 2, -10)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    -- Tick marks for every step when there are only a few (e.g. 1-5)
    local ticks = {}
    if maxV - minV <= 10 then
        for _ = minV, maxV do
            local tk = slider:CreateTexture(nil, "BORDER")
            tk:SetSize(2, 10)
            tk:SetColorTexture(0.5, 0.5, 0.5, 1)
            ticks[#ticks + 1] = tk
        end
    end

    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        db[key] = v
        value:SetText(fmt(v))
        if onChange then onChange(v) end
        ns.UpdateCounts()
    end)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta) end)

    refreshers[#refreshers + 1] = function()
        slider:SetValue(db[key])
        value:SetText(fmt(db[key]))
    end
    measures[#measures + 1] = function() return t:GetStringWidth() + 16 + math.max(30, value:GetStringWidth()) end
    stretchers[#stretchers + 1] = function(w)
        row:SetWidth(w)
        local sw = w - 4
        slider:SetWidth(sw)
        for i, tk in ipairs(ticks) do
            tk:ClearAllPoints()
            tk:SetPoint("CENTER", slider, "LEFT", 5 + (i - 1) * (sw - 10) / (#ticks - 1), 0)
        end
    end
end

-- Integer slider with an input box on the right.
-- o = { label (key or function), icon (function -> texture, optional), min, max, get, set,
--       gap, rows (table that collects the row frames, optional),
--       column ("left" or "right": two sliders share a row, the right one takes the left's),
--       valueText (function v -> text for the box, e.g. a word at the last step; optional) }
local COLUMN_GAP = 20
UI.COLUMN_GAP = COLUMN_GAP -- the General tab's Scale row lays out its column with it
function UI.AddNumberSlider(o)
    local ROW = 42
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(ROW)
    local y
    if o.column == "right" then
        y = page.columnY
    else
        y = Place(ROW, o.gap or 6)
        page.columnY = y
    end
    row:SetPoint("TOPLEFT", INSET, y)
    if o.rows then o.rows[#o.rows + 1] = row end

    local x = 0
    local icon
    if o.icon then
        icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", 0, -1)
        x = 24
    end
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, -4)
    SetL(label, o.label)

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(40, 20)
    box:SetPoint("TOPRIGHT", 0, 0)
    box:SetAutoFocus(false)
    -- A value shown as a word needs letters; digits typed are still read as the number
    box:SetNumeric(not o.valueText)
    box:SetMaxLetters(o.valueText and 0 or #tostring(o.max))
    local function Shown(v) return o.valueText and o.valueText(v) or tostring(v) end
    local probe = o.valueText and row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if probe then probe:Hide() end
    box:SetJustifyH("CENTER")

    local slider = MakeSlider(row)
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -28)
    slider:SetMinMaxValues(o.min, o.max)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local updating = false
    local function SetValue(v)
        v = math.max(o.min, math.min(o.max, math.floor(v + 0.5)))
        o.set(v)
        updating = true
        slider:SetValue(v)
        updating = false
        box:SetText(Shown(v))
        ns.UpdateCounts()
    end
    slider:SetScript("OnValueChanged", function(_, v)
        if not updating then SetValue(v) end
    end)
    slider:SetScript("OnMouseWheel", function(_, delta) SetValue(o.get() + delta) end)

    box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then SetValue(v) else self:SetText(Shown(o.get())) end
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(Shown(o.get()))
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self) self:SetText(Shown(o.get())) end)

    refreshers[#refreshers + 1] = function()
        if type(o.label) == "function" then label:SetText(o.label()) end -- e.g. item names
        if icon then icon:SetTexture(o.icon()) end
        updating = true
        slider:SetValue(o.get())
        updating = false
        box:SetText(Shown(o.get()))
    end
    -- A column needs room for two halves its width, so no label in either is cut
    measures[#measures + 1] = function()
        local boxW = 40
        if o.valueText then -- room for the word at the last step, in the current language
            probe:SetText(o.valueText(o.max))
            boxW = math.max(40, probe:GetStringWidth() + 16)
            box:SetWidth(boxW)
        end
        local need = x + label:GetStringWidth() + 16 + boxW
        if o.column then return 2 * need + COLUMN_GAP end
        return need
    end
    stretchers[#stretchers + 1] = function(w)
        local rowW = o.column and (w - COLUMN_GAP) / 2 or w
        row:SetWidth(rowW)
        slider:SetWidth(rowW - 4)
        if o.column == "right" then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", INSET + (w + COLUMN_GAP) / 2, y)
        end
    end
end

-- Highlight speed: 5 steps, 3 = default. The glow's duration follows at once (ns.ApplyLook).
function UI.AddSpeedSlider(key)
    UI.AddIntSlider("OPT_ANTS_SPEED", key, 1, #D.GLOW_DURATIONS, function(v)
        return v == 3 and (v .. " (" .. L.DEFAULT .. ")") or tostring(v)
    end, nil, function() ns.ApplyLook() end)
end

-- Centered separator line in WoW style: 2 px gold, strong in the middle, fading to the ends.
-- PixelUtil (Retail) snaps height and position to real screen pixels, so all lines look
-- equally thick regardless of UI scale and position.
local SEP_HEIGHT = 2
local SEP_R, SEP_G, SEP_B = 1, 0.82, 0
function UI.AddSeparator()
    local y = Place(SEP_HEIGHT, 10)
    page.cursorY = page.cursorY - 4 -- some air above and below the line
    y = math.floor(y - 4)

    -- Two halves with a gradient: transparent outside, full gold in the middle
    local left = page:CreateTexture(nil, "ARTWORK")
    local right = page:CreateTexture(nil, "ARTWORK")
    local halves = { left, right }
    for _, tex in ipairs(halves) do
        tex:SetColorTexture(1, 1, 1, 1)
        if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end
        if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    end
    left:SetPoint("TOPRIGHT", page, "TOP", 0, y)
    right:SetPoint("TOPLEFT", page, "TOP", 0, y)

    local gradientOk = false
    if CreateColor then
        local edge, mid = CreateColor(SEP_R, SEP_G, SEP_B, 0), CreateColor(SEP_R, SEP_G, SEP_B, 0.9)
        gradientOk = pcall(left.SetGradient, left, "HORIZONTAL", edge, mid)
            and pcall(right.SetGradient, right, "HORIZONTAL", mid, edge)
    end
    if not gradientOk then
        -- Older clients: plain line
        left:SetColorTexture(SEP_R, SEP_G, SEP_B, 0.75)
        right:SetColorTexture(SEP_R, SEP_G, SEP_B, 0.75)
    end

    stretchers[#stretchers + 1] = function(w)
        local half = math.floor(w * 0.4)
        for _, tex in ipairs(halves) do
            if PixelUtil then
                PixelUtil.SetSize(tex, half, SEP_HEIGHT)
            else
                tex:SetSize(half, SEP_HEIGHT)
            end
        end
    end
end

-- Dropdown with the label on the left and the selection on the right.
-- options = { { value =, text = function }, ... }. Uses the Retail menu dropdown when
-- available, otherwise the classic UIDropDownMenu. Returns its refresh function.
local DD_WIDTH = 180
-- Room a dropdown keeps beside its text: the text inset and the arrow
local DD_TEXT_PAD = 50
UI.DD_TEXT_PAD = DD_TEXT_PAD
local ddCount = 0
function UI.AddDropdown(labelKey, options, get, set)
    local ROW = 28
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", INSET, Place(ROW, 6))

    local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", 0, 0)
    SetL(t, labelKey)

    local function CurrentText()
        for _, opt in ipairs(options) do
            if get() == opt.value then return opt.text() end
        end
        return ""
    end

    -- Entry lengths differ per language ("简体中文 (Chinese S.)" was cut short at a fixed
    -- 180 px), so the dropdown grows to its longest entry, measured in its own font.
    local width = DD_WIDTH
    local probe = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    probe:Hide()
    local function FitWidth(textRegion)
        local font = textRegion and textRegion:GetFontObject()
        if font then probe:SetFontObject(font) end
        local widest = 0
        for _, opt in ipairs(options) do
            probe:SetText(opt.text())
            widest = math.max(widest, probe:GetStringWidth())
        end
        width = math.max(DD_WIDTH, math.ceil(widest) + DD_TEXT_PAD)
    end

    -- Feature detection: creating the frame fails on clients without the menu dropdown
    -- (the "DropdownButton" frame type or the template does not exist there)
    local refresh
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        -- Retail menu dropdown
        dd:SetWidth(DD_WIDTH)
        dd:SetPoint("RIGHT", 0, 0)
        -- SetupMenu builds the menu right away, but the settings only exist after login,
        -- so it is set up when the window is shown for the first time.
        local isSetup = false
        refresh = function()
            if not db then return end
            FitWidth(dd.Text)
            dd:SetWidth(width)
            if not isSetup then
                isSetup = true
                dd:SetupMenu(function(_, root)
                    for _, opt in ipairs(options) do
                        root:CreateRadio(opt.text(),
                            function() return db and get() == opt.value end,
                            function() set(opt.value) end)
                    end
                end)
            else
                dd:GenerateMenu()
            end
        end
    else
        -- Classic dropdown (the template needs a global name)
        ddCount = ddCount + 1
        dd = CreateFrame("Frame", "SimpleConjureBarDropdown" .. ddCount, row, "UIDropDownMenuTemplate")
        dd:SetPoint("RIGHT", 16, -2) -- the template has invisible padding on both sides
        UIDropDownMenu_SetWidth(dd, DD_WIDTH - 30)
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, opt in ipairs(options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.text()
                info.checked = (get() == opt.value)
                info.func = function()
                    set(opt.value)
                    UIDropDownMenu_SetText(dd, opt.text())
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        refresh = function()
            if not db then return end
            FitWidth(_G[dd:GetName() .. "Text"])
            UIDropDownMenu_SetWidth(dd, width - 30)
            UIDropDownMenu_SetText(dd, CurrentText())
        end
    end

    refreshers[#refreshers + 1] = refresh
    measures[#measures + 1] = function() return t:GetStringWidth() + 16 + width end
    stretchers[#stretchers + 1] = function(w) row:SetWidth(w) end
    return refresh
end

-- Push button sized to its (localized) text
function UI.AddButton(parent, labelKey, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(22)
    SetL(b, labelKey)
    b:SetScript("OnClick", onClick)
    local function Fit() b:SetWidth(b:GetFontString():GetStringWidth() + 30) end
    Fit()
    refreshers[#refreshers + 1] = Fit
    return b
end

---------------------------------------------------------------------------
-- Color picker (Blizzard ColorPickerFrame, Retail 10.2.5+ and older API)
---------------------------------------------------------------------------
local function PickerGetAlpha()
    if ColorPickerFrame.GetColorAlpha then return ColorPickerFrame:GetColorAlpha() end
    if OpacitySliderFrame then return 1 - OpacitySliderFrame:GetValue() end
    return 1
end

local function PickerSetColor(r, g, b, a)
    local cp = ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker
    if cp then
        cp:SetColorRGB(r, g, b)
        if cp.SetColorAlpha then cp:SetColorAlpha(a) end
    else
        ColorPickerFrame:SetColorRGB(r, g, b)
        if OpacitySliderFrame then OpacitySliderFrame:SetValue(1 - a) end
    end
end

-- "Default" button right below the color picker, only shown when SimpleConjureBar opened it
local defaultBtn = CreateFrame("Button", nil, ColorPickerFrame, "UIPanelButtonTemplate")
defaultBtn:SetSize(110, 22)
defaultBtn:SetPoint("TOP", ColorPickerFrame, "BOTTOM", 0, -2)
SetL(defaultBtn, "DEFAULT")
defaultBtn:Hide()
defaultBtn:SetScript("OnClick", function()
    local key = defaultBtn.key
    if not key then return end
    local d = D.COLOR_DEFAULTS[key]
    db[key] = ns.CopyColor(d)
    PickerSetColor(d.r, d.g, d.b, d.a)
    ns.ApplyLook()
    if defaultBtn.onDefault then defaultBtn.onDefault() end
end)
ColorPickerFrame:HookScript("OnHide", function() defaultBtn:Hide() end)

-- key: name of the color in the settings (e.g. "bg")
local function OpenColorPicker(key, onChange)
    local old = ns.CopyColor(db[key])

    local function Changed()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        db[key] = { r = r, g = g, b = b, a = PickerGetAlpha() }
        ns.ApplyLook()
        if onChange then onChange() end
    end
    local function Cancel()
        db[key] = old
        ns.ApplyLook()
        if onChange then onChange() end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = old.r, g = old.g, b = old.b, opacity = old.a, hasOpacity = true,
            swatchFunc = Changed, opacityFunc = Changed, cancelFunc = Cancel,
        })
    else
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - old.a
        ColorPickerFrame.previousValues = old
        ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = Changed, Changed, Cancel
        ColorPickerFrame:SetColorRGB(old.r, old.g, old.b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end

    defaultBtn.key, defaultBtn.onDefault = key, onChange
    defaultBtn:Show()
end

-- Color swatch button: a click opens the WoW color picker (with the "Default" button)
local function CreateSwatchButton(parent, key)
    local swatch = CreateFrame("Button", nil, parent, API.BACKDROP_TPL)
    swatch:SetSize(22, 22)
    if swatch.SetBackdrop then
        swatch:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end
    local checker = swatch:CreateTexture(nil, "BACKGROUND")
    checker:SetPoint("TOPLEFT", 3, -3)
    checker:SetPoint("BOTTOMRIGHT", -3, 3)
    checker:SetColorTexture(1, 1, 1, 1)
    local color = swatch:CreateTexture(nil, "ARTWORK")
    color:SetAllPoints(checker)

    local function Update()
        local c = db[key]
        color:SetColorTexture(c.r, c.g, c.b, c.a)
        ns.UpdateCounts()
    end
    swatch:SetScript("OnClick", function() OpenColorPicker(key, Update) end)
    swatch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.OPT_BG_TIP)
        GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", GameTooltip_Hide)
    refreshers[#refreshers + 1] = Update
    return swatch
end

-- Color swatch with label in its own row
function UI.AddSwatch(labelKey, key, gap)
    local swatch = CreateSwatchButton(page, key)
    swatch:SetPoint("TOPLEFT", INSET, Place(22, gap or 6))
    local t = swatch:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    SetL(t, labelKey)
    measures[#measures + 1] = function() return 22 + 8 + t:GetStringWidth() end
end

-- One row: optional check box followed by any number of color swatches.
-- colors = { { label = key, key = dbKey }, ... }
function UI.AddToggleColorRow(checkLabelKey, checkKey, onChange, colors)
    local ROW, SPACING = 26, 18
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", INSET - 3, Place(ROW, 6))

    local cbText
    if checkKey then
        local cb
        cb, cbText = CreateCheck(row, checkLabelKey, checkKey, onChange)
        cb:SetPoint("LEFT", 0, 0)
    end

    local items = {}
    for _, c in ipairs(colors) do
        local sw = CreateSwatchButton(row, c.key)
        local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        SetL(t, c.label)
        items[#items + 1] = { sw = sw, text = t }
    end

    -- Positions depend on the text widths of the current language
    local function Arrange()
        local x = cbText and (26 + 4 + cbText:GetStringWidth() + SPACING) or 3
        for _, it in ipairs(items) do
            it.sw:ClearAllPoints()
            it.sw:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + 22 + 6 + it.text:GetStringWidth() + SPACING
        end
        row.needW = x - SPACING - 3
    end
    refreshers[#refreshers + 1] = Arrange
    measures[#measures + 1] = function() return row.needW or 0 end
    stretchers[#stretchers + 1] = function(w) row:SetWidth(w + 3) end
end

---------------------------------------------------------------------------
-- Tabs and window layout (called by SettingsPages.lua once all pages exist)
---------------------------------------------------------------------------
local tabs, activePage = {}, 1

local function ShowPage(i)
    activePage = i
    for k, pg in ipairs(pages) do
        local tb = tabs[k]
        if k == i then
            pg:Show()
            tb:LockHighlight()
            tb:GetFontString():SetTextColor(1, 0.82, 0)
        else
            pg:Hide()
            tb:UnlockHighlight()
            tb:GetFontString():SetTextColor(1, 1, 1)
        end
    end
end

-- Tabs next to each other, width by text
local function ArrangeTabs()
    local x = INSET
    for _, tb in ipairs(tabs) do
        tb:SetWidth(tb:GetFontString():GetStringWidth() + 24)
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", settings, "TOPLEFT", x, -46)
        x = x + tb:GetWidth() + 4
    end
    return x - 4 - INSET
end

-- Width and height follow the content (the tallest page sets the height)
local function LayoutSettings()
    local contentW = MIN_W
    for _, m in ipairs(measures) do contentW = math.max(contentW, math.ceil(m())) end
    for _, st in ipairs(stretchers) do st(contentW) end
    settings:SetWidth(contentW + 2 * INSET)
    local lowest = 0
    for _, pg in ipairs(pages) do lowest = math.min(lowest, pg.cursorY) end
    -- cursorY points below the last element; replace the last gap with the border
    settings:SetHeight(-lowest - 4 + INSET)
    UI.Placed()
end

local function RefreshAll()
    for _, f in ipairs(refreshers) do f() end
    LayoutSettings()
    ShowPage(activePage)
end

function UI.CreateTabs()
    for i, pg in ipairs(pages) do
        local tb = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
        tb:SetHeight(22)
        SetL(tb, pg.titleKey)
        tb:SetScript("OnClick", function() ShowPage(i) end)
        tabs[i] = tb
    end
    measures[#measures + 1] = ArrangeTabs
end

-- Reloads all values into an open window (after chat commands)
function ns.RefreshSettingsWindow()
    if settings:IsShown() then
        for _, f in ipairs(refreshers) do f() end
    end
end

ns.OnLanguageChanged(function()
    ArrangeTabs()
    if settings:IsShown() then RefreshAll() end
end)

---------------------------------------------------------------------------
-- Show / hide, combat handling
---------------------------------------------------------------------------
settings:SetScript("OnShow", function()
    -- The menu cannot be opened in combat (/scb, minimap, handle or WoW options)
    if InCombatLockdown() then
        settings:Hide()
        -- only a chat command gets an answer in the chat; a click is refused silently
        if ns.fromCommand then Print(L.MENU_COMBAT) end
        return
    end
    ns.ApplyWindowOpacity(settings)
    RefreshAll()
end)

function ns.ToggleSettings()
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

-- aboveBlizzard: opened from the WoW options; the window is raised above the Blizzard
-- settings panel for as long as it is open
function ns.CloseSettings()
    settings:Hide()
end

-- tab: the title key of a tab to show, e.g. "TAB_TRACKING" from the Intellect button's right click
function ns.OpenSettings(aboveBlizzard, tab)
    if aboveBlizzard then settings:SetFrameStrata("FULLSCREEN_DIALOG") end
    for i, pg in ipairs(pages) do
        if tab and pg.titleKey == tab then ShowPage(i) end
    end
    if settings:IsShown() then settings:Raise() else settings:Show() end
end
settings:HookScript("OnHide", function()
    settings:SetFrameStrata("DIALOG")
    ns.LogSettings() -- what changed, for the bug report's action log
end)

-- Combat start: close the window and reopen it afterwards if it was closed because of combat
do
    local reopenAfterCombat = false
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if settings:IsShown() then
                reopenAfterCombat = true
                settings:Hide()
            end
        elseif reopenAfterCombat then
            reopenAfterCombat = false
            settings:Show()
        end
    end)
end
