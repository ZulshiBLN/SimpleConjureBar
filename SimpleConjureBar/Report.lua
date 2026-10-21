-- SimpleConjureBar - bug report window
-- Addons cannot send data, open a browser or write to the clipboard. The window therefore builds
-- a ready-made report (addon version, client, language, settings and this addon's Lua errors from
-- BugGrabber/BugSack) in a selected text box: the user copies it with Ctrl+C and pastes it as a new
-- issue. No character name, realm or other personal data is included.

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local SetL = ns.SetL

local db
ns.OnDBReady(function(d) db = d end)

local MAX_ERRORS = 5       -- newest errors of this addon included in the report
local MAX_STACK_LINES = 12 -- stack lines per error
local MAX_ADDONS = 60      -- loaded addons named in the report

---------------------------------------------------------------------------
-- State snapshot (ruleset plan 2026-10-17-bug-report-details): what decides a misbehaviour
-- without a Lua error - each button's click, the items the addon counts, the group by class,
-- own buffs - as IDs, tokens and counts. /scb debug prints the same lines.
---------------------------------------------------------------------------
local ATTRS = { "type", "spell", "item", "unit", "macrotext" }

local function ButtonLine(label, b)
    local parts = { "button " .. label, "shown=" .. tostring(b:IsShown()) }
    for _, suffix in ipairs({ "", "1", "2", "3" }) do
        for _, a in ipairs(ATTRS) do
            local v = b:GetAttribute(a .. suffix)
            if v ~= nil then
                parts[#parts + 1] = a .. suffix .. "=" .. (a == "macrotext" and ns.SafeMacro(v) or ns.SafeValue(v))
            end
        end
    end
    local source = b:GetAttribute("scbsource")
    if source then parts[#parts + 1] = "scbsource=" .. ns.SafeValue(source) end
    return table.concat(parts, " ")
end

-- The items the addon conjures, uses or buys, by ID
local function TrackedItems()
    local ids = {}
    for _, list in ipairs({ D.WATER_ITEMS, D.FOOD_ITEMS }) do
        for _, id in ipairs(list) do ids[#ids + 1] = id end
    end
    for _, g in ipairs(D.MANA_GEMS) do ids[#ids + 1] = g.item end
    for _, r in ipairs(D.REAGENTS) do ids[#ids + 1] = r.id end
    return ids
end

local function OwnBuffs()
    local parts = {}
    local GetAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local ok, aura = pcall(GetAura, "player", i, "HELPFUL")
        if not ok or not aura then break end
        local okLeft, left = pcall(function()
            local e = aura.expirationTime
            if type(e) == "number" and e > 0 then return math.floor((e - GetTime()) / 60 + 0.5) .. "m" end
            return "-"
        end)
        local okId, id = pcall(tostring, aura.spellId)
        parts[#parts + 1] = (okId and id or "?") .. ":" .. (okLeft and left or "?")
    end
    return table.concat(parts, " ")
end

local function GroupLine()
    local kind = IsInRaid() and "raid" or IsInGroup() and "party" or "solo"
    local units, size = { "player" }, 1
    if IsInRaid() then
        size = GetNumGroupMembers()
        units = {}
        for i = 1, size do units[i] = "raid" .. i end
    elseif IsInGroup() then
        size = GetNumSubgroupMembers() + 1
        for i = 1, size - 1 do units[#units + 1] = "party" .. i end
    end
    local byClass, classes = {}, {}
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        if class then
            if not byClass[class] then classes[#classes + 1] = class end
            byClass[class] = (byClass[class] or 0) + 1
        end
    end
    table.sort(classes)
    local parts = {}
    for _, c in ipairs(classes) do parts[#parts + 1] = c .. "=" .. byClass[c] end
    return ("group %s size=%d %s"):format(kind, size, table.concat(parts, " "))
end

function ns.StateSnapshot()
    local lines = {}
    for _, key in ipairs(D.DEFAULT_ORDER) do
        local b = ns.buttons[key]
        lines[#lines + 1] = ButtonLine(key, b)
        for _, c in ipairs(b.fly and b.fly.buttons or {}) do lines[#lines + 1] = ButtonLine(c:GetName(), c) end
    end
    for _, b in ipairs({ ns.buffKey, _G.SimpleConjureBarBuffRun }) do
        lines[#lines + 1] = ButtonLine(b:GetName(), b)
    end
    local bags = {}
    for _, id in ipairs(TrackedItems()) do
        local n = API.ItemCount(id) or 0
        if n > 0 then bags[#bags + 1] = id .. "=" .. n end
    end
    lines[#lines + 1] = "bags " .. table.concat(bags, " ")
    lines[#lines + 1] = GroupLine()
    lines[#lines + 1] = "buffs " .. OwnBuffs()
    lines[#lines + 1] = "keydown " .. tostring(GetCVar("ActionButtonUseKeyDown"))
    lines[#lines + 1] = "combat " .. (InCombatLockdown() and "yes" or "no")
    return lines
end

-- Loaded addons by folder name - the title may carry colour codes - and declared version
function ns.AddonList()
    local lines, extra = {}, 0
    for i = 1, C_AddOns.GetNumAddOns() do
        if C_AddOns.IsAddOnLoaded(i) then
            if #lines < MAX_ADDONS then
                local name = C_AddOns.GetAddOnInfo(i)
                lines[#lines + 1] = name .. " " .. tostring(C_AddOns.GetAddOnMetadata(name, "Version") or "?")
            else
                extra = extra + 1
            end
        end
    end
    if extra > 0 then lines[#lines + 1] = ("... %d more"):format(extra) end
    return lines
end

---------------------------------------------------------------------------
-- Report content
---------------------------------------------------------------------------
-- This addon's errors of the current session from BugGrabber (the error collector BugSack
-- builds on), newest first. Errors of earlier sessions come from BugGrabber's saved data and
-- stay out; without a session number, an error from before this addon loaded counts as one.
local function CollectErrors()
    local list = {}
    local grabber = BugGrabber
    if not (grabber and grabber.GetDB) then return list, false end
    local ok, errors = pcall(grabber.GetDB, grabber)
    if not ok or type(errors) ~= "table" then return list, true end
    local okSession, session = pcall(function() return grabber.GetSessionId and grabber:GetSessionId() end)
    if not okSession then session = nil end
    for i = #errors, 1, -1 do
        local e = errors[i]
        if type(e) == "table" then
            local current
            if type(session) == "number" and type(e.session) == "number" then
                current = e.session == session
            else
                current = type(e.time) == "number" and e.time >= ns.logStartClock
            end
            local text = tostring(e.message or "") .. "\n" .. tostring(e.stack or "")
            if current and text:find(ns.ADDON_NAME, 1, true) then
                list[#list + 1] = e
                if #list >= MAX_ERRORS then break end
            end
        end
    end
    return list, true
end

-- The first lines of a text, each with the tag of its report field and filtered
local function FirstLines(text, max, tag, names)
    local out, n = {}, 0
    for line in tostring(text or ""):gmatch("[^\n]+") do
        n = n + 1
        if n > max then out[#out + 1] = tag .. " ..." break end
        out[#out + 1] = tag .. " " .. ns.Scrub(line, names)
    end
    return out
end

-- When an error came, relative only - no date or clock in a report - and whether in combat
local function ErrorWhen(e)
    if type(e.time) ~= "number" then return "time unknown", "unknown" end
    local when = ("%d min ago"):format(math.floor((time() - e.time) / 60 + 0.5))
    local since = e.time - ns.logStartClock
    if since >= 0 then when = when .. (", %d s after login"):format(since) end
    return when, ns.CombatAt(e.time)
end

local function OrDash(s) return (s and s ~= "") and s or "-" end

-- The settings the addon knows, sorted by name, values by allowlist; a key it does not know
-- is left out (it could hold anything). Tables are summarized.
local SETTINGS_EXTRA = { "point", "rel", "dbVersion" }
local function SettingsText()
    if not db then return "(not loaded)" end
    local keys = {}
    for k in pairs(D.VALUE_DEFAULTS) do keys[#keys + 1] = k end
    for _, k in ipairs(SETTINGS_EXTRA) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = db[k]
        local t = type(v)
        if t == "number" or t == "boolean" or t == "string" then parts[#parts + 1] = k .. "=" .. ns.SafeValue(v) end
    end
    if type(db.order) == "table" then
        local order = {}
        for i, key in ipairs(db.order) do order[i] = ns.SafeValue(key) end
        parts[#parts + 1] = "order=" .. table.concat(order, ",")
    end
    if type(db.amounts) == "table" then
        local a = {}
        for _, r in ipairs(D.REAGENTS) do a[#a + 1] = r.id .. ":" .. tostring(db.amounts[r.id]) end
        parts[#parts + 1] = "amounts=" .. table.concat(a, ",")
    end
    return table.concat(parts, ", ")
end

-- form: { description, area (a key of D.REPORT_AREAS), details }
-- The level in a band of ten: enough for ranks, too coarse to tell a character apart
local function LevelBand()
    local low = math.floor((tonumber(UnitLevel("player")) or 0) / 10) * 10
    return ("%d-%d"):format(low, low + 9)
end

-- Every line belongs to a field of D.REPORT_FIELDS (Privacy.lua, ruleset plan
-- 2026-10-17-bug-report-details). form: { description, area (a key of D.REPORT_AREAS), details }
local function BuildReport(form)
    ns.LogSettings()
    -- A secret name could not be filtered: no report at all, not one without the filter
    local names = ns.KnownNames()
    if not names then return nil end
    local version, build, _, interface = GetBuildInfo()
    local _, classFile = UnitClass("player")
    local lines = {
        "## SimpleConjureBar bug report",
        "",
        "**Description:** " .. OrDash(ns.Scrub(form.description, names)),
        "**Area:** " .. form.area,
        "**Details:** " .. OrDash(ns.Scrub(form.details, names)),
        "",
        "- Addon version: " .. ns.VERSION,
        "- Client: " .. tostring(version) .. " (build " .. tostring(build) .. ", interface " .. tostring(interface) .. ")",
        "- Client locale: " .. tostring(GetLocale()) .. ", addon language: "
            .. tostring((SimpleConjureBarGlobalDB and SimpleConjureBarGlobalDB.language) or "auto"),
        "- Character: " .. tostring(classFile) .. ", level " .. LevelBand()
            .. (IsInRaid() and ", raid" or IsInGroup() and ", party" or ", solo"),
        "- Settings: " .. SettingsText(),
        "",
    }
    local errors, hasGrabber = CollectErrors()
    if not hasGrabber then
        lines[#lines + 1] = "**Lua errors:** BugGrabber/BugSack not installed"
    elseif #errors == 0 then
        lines[#lines + 1] = "**Lua errors:** none from SimpleConjureBar in this session"
    else
        lines[#lines + 1] = "**Lua errors (newest first):**"
        for i, e in ipairs(errors) do
            local when, combat = ErrorWhen(e)
            lines[#lines + 1] = ""
            lines[#lines + 1] = ("Error %d (x%s, %s, combat: %s):"):format(i, tostring(e.counter or 1), when, combat)
            lines[#lines + 1] = "```"
            for _, l in ipairs(FirstLines(e.message, 6, "msg", names)) do lines[#lines + 1] = l end
            for _, l in ipairs(FirstLines(e.stack, MAX_STACK_LINES, "at", names)) do lines[#lines + 1] = l end
            for _, l in ipairs(ns.SafeLocals(e.locals, names)) do lines[#lines + 1] = "local " .. l end
            lines[#lines + 1] = "```"
        end
    end
    local function Block(title, tag, list, scrub)
        lines[#lines + 1] = ""
        lines[#lines + 1] = title
        lines[#lines + 1] = "```"
        for _, l in ipairs(list) do lines[#lines + 1] = tag .. " " .. (scrub and ns.Scrub(l, names) or l) end
        lines[#lines + 1] = "```"
    end
    Block("**Last actions (seconds since login):**", "log", ns.LogLines())
    Block("**State:**", "state", ns.StateSnapshot())
    Block("**Loaded addons:**", "addon", ns.AddonList(), true)
    return ns.CapReport(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame
local MAX_TEXT = 500 -- letters of the description and of the details

-- The box shows the code, selected for Ctrl+C, or - "Show content" - the readable report,
-- never selected, so what gets copied is the code (ruleset plan 2026-10-21-bug-report-code)
local function Shown() return frame.showContent and frame.reportText or frame.codeText end

local function MarkSelection()
    if frame.showContent then frame.report:HighlightText(0, 0) else frame.report:HighlightText() end
end

local function SelectReport()
    frame.report:SetFocus()
    MarkSelection()
end

local function FormValues()
    return { description = frame.desc:GetText(), area = frame.area, details = frame.details:GetText() }
end

local function ShowBox()
    frame.report:SetText(Shown())
    frame.report:SetCursorPosition(0)
    MarkSelection()
    SetL(frame.toggle, frame.showContent and "REPORT_SHOW_CODE" or "REPORT_SHOW_CONTENT")
end

-- Each keystroke rebuilds the report; while a name is secret the last clean one stays
local function Refresh()
    local text = BuildReport(FormValues())
    if not text then
        ns.Print(L.REPORT_SECRET)
        return
    end
    frame.reportText = text
    frame.codeText = ns.ReportCode.Encode(text)
    ShowBox()
end

-- A one-line text field: typing rebuilds the report, Enter selects it for copying
local function AddInput(anchor, width)
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -4)
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(MAX_TEXT)
    box:SetScript("OnTextChanged", function(_, userInput) if userInput then Refresh() end end)
    box:SetScript("OnEnterPressed", SelectReport)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function CreateWindow()
    local W, H, PAD = 520, 580, 22
    frame = CreateFrame("Frame", "SimpleConjureBarReport", UIParent, API.BACKDROP_TPL)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    -- Docked beside the settings window, a drag moves that window and the report goes with it
    local function Mover() return frame.docked and ns.UI.window or frame end
    frame:SetScript("OnDragStart", function() Mover():StartMoving() end)
    frame:SetScript("OnDragStop", function() Mover():StopMovingOrSizing() end)
    frame:SetClampedToScreen(true)
    -- Closing the settings closes a report docked to them
    -- Combat closes both windows, each from its own event, in no set order: whichever closes
    -- the report first marks it to come back once the settings are back
    local reopen = false
    ns.UI.window:HookScript("OnHide", function()
        if frame.docked and frame:IsShown() then
            if UnitAffectingCombat("player") then reopen = true end
            frame:Hide()
        end
    end)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    tinsert(UISpecialFrames, "SimpleConjureBarReport") -- closes with Escape

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    SetL(title, "REPORT_TITLE")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- What the report holds and never holds, and that an issue is public (ruleset plan
    -- 2026-10-17-bug-report-details, item 7)
    local privacy = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    privacy:SetPoint("TOPLEFT", PAD, -44)
    privacy:SetWidth(W - 2 * PAD)
    privacy:SetJustifyH("LEFT")
    SetL(privacy, "REPORT_PRIVACY")
    local public = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    public:SetPoint("TOPLEFT", privacy, "BOTTOMLEFT", 0, -4)
    public:SetWidth(W - 2 * PAD)
    public:SetJustifyH("LEFT")
    SetL(public, "REPORT_PUBLIC")

    -- Step 1: what happened, where (a list, so the developer knows where to look), details
    local step1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step1:SetPoint("TOPLEFT", public, "BOTTOMLEFT", 0, -10)
    SetL(step1, "REPORT_STEP1")
    frame.desc = AddInput(step1, W - 2 * PAD - 6)

    local where = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    where:SetPoint("TOPLEFT", frame.desc, "BOTTOMLEFT", -6, -14)
    SetL(where, "REPORT_WHERE")
    frame.area = "OTHER"
    local menu = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    menu:SetPoint("LEFT", where, "RIGHT", 12, 0)
    menu:SetWidth(240)
    menu:SetupMenu(function(_, root)
        for _, key in ipairs(D.REPORT_AREAS) do
            root:CreateRadio(L["AREA_" .. key], function() return frame.area == key end,
                function() frame.SetArea(key) end)
        end
    end)
    frame.areaMenu = menu
    function frame.SetArea(key)
        frame.area = key
        menu:GenerateMenu()
        Refresh()
    end
    -- The dropdown shows its selection's text as of its last generation: a language switch
    -- kept the old language's word (in game, 2026-10-21)
    ns.OnLanguageChanged(function() menu:GenerateMenu() end)

    local detailsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailsLabel:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -16)
    SetL(detailsLabel, "REPORT_DETAILS")
    frame.details = AddInput(detailsLabel, W - 2 * PAD - 6)

    -- Step 2: the report, selected for Ctrl+C (read-only)
    local step2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step2:SetPoint("TOPLEFT", frame.details, "BOTTOMLEFT", -6, -12)
    SetL(step2, "REPORT_STEP2")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", step2, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 92)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", scroll, -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, 24, -4)
    bg:SetColorTexture(0, 0, 0, 0.5)

    local report = CreateFrame("EditBox", nil, scroll)
    report:SetMultiLine(true)
    report:SetAutoFocus(false)
    report:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    report:SetWidth(W - 2 * PAD - 30)
    report:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    report:SetScript("OnEditFocusGained", MarkSelection)
    -- Read-only: user edits are undone right away, back to what the box shows
    report:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(Shown() or "")
            MarkSelection()
        end
    end)
    scroll:SetScrollChild(report)
    frame.report = report

    -- Step 3: where to paste it
    local step3 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step3:SetPoint("BOTTOMLEFT", PAD, 66)
    step3:SetPoint("RIGHT", -PAD, 0)
    step3:SetJustifyH("LEFT")
    local url = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    url:SetPoint("BOTTOMLEFT", PAD + 6, 40)
    url:SetSize(W - 2 * PAD - 6, 22)
    url:SetAutoFocus(false)
    url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    url:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(D.BUG_REPORT_URL) self:HighlightText() end
    end)
    url:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if D.BUG_REPORT_URL ~= "" then
        SetL(step3, "REPORT_STEP3")
        url:SetText(D.BUG_REPORT_URL)
    else
        SetL(step3, "REPORT_NO_URL")
        url:Hide()
    end

    local done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    done:SetSize(120, 22)
    done:SetPoint("BOTTOMRIGHT", -PAD, 16)
    SetL(done, "CLOSE")
    done:SetScript("OnClick", function() frame:Hide() end)

    local toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggle:SetSize(160, 22)
    toggle:SetPoint("BOTTOMLEFT", PAD, 16)
    toggle:SetScript("OnClick", function()
        frame.showContent = not frame.showContent
        ShowBox()
    end)
    frame.toggle = toggle

    -- Built out of combat only: names and auras are readable then (phase 1 research - aura
    -- reads raise an error in combat). The window closes when combat starts and comes back
    -- after it, as the settings window does.
    frame:SetScript("OnShow", function()
        if InCombatLockdown() then
            frame:Hide()
            ns.Print(L.REPORT_COMBAT)
            return
        end
        -- A secret name could not be filtered: no report until it is readable again
        if not ns.KnownNames() then
            frame:Hide()
            ns.Print(L.REPORT_SECRET)
            return
        end
        Refresh()
        SelectReport()
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if frame:IsShown() then reopen = true; frame:Hide() end
        elseif reopen then
            reopen = false
            -- after the settings window's own handler, which may run after this one
            C_Timer.After(0, function()
                if not frame.docked or ns.UI.window:IsShown() then frame:Show() end
            end)
        end
    end)
    function frame.BuildText() return BuildReport(FormValues()) end
    frame:Hide()
end

function ns.OpenBugReport()
    if not frame then CreateWindow() end
    -- With the settings window open it stays, and the report opens docked to its left
    -- (Michel, 2026-10-21); else in the middle of the screen
    frame:ClearAllPoints()
    frame.docked = ns.UI.window:IsShown()
    if frame.docked then
        frame:SetPoint("TOPRIGHT", ns.UI.window, "TOPLEFT", -4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame.desc:SetText("")
    frame.details:SetText("")
    frame.area = "OTHER"
    frame.areaMenu:GenerateMenu()
    frame.showContent = false
    if frame:IsShown() then Refresh() SelectReport() else frame:Show() end
end
