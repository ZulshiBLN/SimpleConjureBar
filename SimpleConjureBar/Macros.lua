-- SimpleConjureBar - macro helper
-- Creates the character macros of the Macros tab (or updates them when they exist):
-- "SCB Polymorph", the Ice Block macro and the stopcasting macros.
--   Polymorph, first click without focus: the hostile, living target becomes the focus and gets
--   the raid marker chosen in the Macros tab (default: moon). Further clicks: Polymorph on the
--   focus. A dead focus is cleared automatically.
-- /tm is used for the marker: SetRaidTarget is protected and cannot be called from /run.

local _, ns = ...
if not ns.enabled then return end

local D, L = ns.D, ns.L

local db
ns.OnDBReady(function(d) db = d end)

local MACRO_NAME = "SCB Polymorph"
local MACRO_ICON = "INV_MISC_QUESTIONMARK" -- #showtooltip shows the spell icon instead

local function MacroBody()
    -- The spell name must match the client language, so it comes from the client
    local spell = ns.SpellName(D.SPELL_POLYMORPH) or "Polymorph"
    return table.concat({
        "#showtooltip " .. spell,
        "/clearfocus [@focus,dead]",
        "/cast [@focus,harm,nodead] " .. spell,
        "/stopmacro [@focus,exists]",
        "/focus [@target,harm,nodead]",
        "/tm [@focus,harm,nodead] " .. db.macroMarker, -- raid marker chosen in the Macros tab
    }, "\n")
end

-- Opens Blizzard's macro window on the character macros (where "SCB Polymorph" is stored)
function ns.ShowMacroWindow()
    if InCombatLockdown() then ns.Print(L.NOT_IN_COMBAT) return end
    if ShowMacroFrame then
        ShowMacroFrame()
    else
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then load("Blizzard_MacroUI") end
        if MacroFrame then ShowUIPanel(MacroFrame) end
    end
    -- Tab 2 = character macros, where every SCB macro lives. The window switches to tab 1
    -- when shown, so this comes after. ChangeTab takes the tab number; SelectTab takes the
    -- tab button and errored on a number (Blizzard_MacroUI). Older clients: the tab button.
    -- The settings window stays open (Michel's choice, 2026-10-18).
    if MacroFrame then
        if MacroFrame.ChangeTab then
            MacroFrame:ChangeTab(2)
        elseif MacroFrameTab2 and MacroFrameTab2.Click then
            MacroFrameTab2:Click()
        end
    end
end

-- The character macro of that name. Character macros use the indexes after the account-wide
-- ones; GetMacroIndexByName finds an account-wide macro of the same name first.
local function CharacterMacroIndex(name, maxAccount)
    local _, characterMacros = GetNumMacros()
    for index = maxAccount + 1, maxAccount + characterMacros do
        if GetMacroInfo(index) == name then return index end
    end
end

-- Creates the character macro `name`, or updates it when it exists. A player's account-wide
-- macro of the same name is left alone (code review 1.1.0, F-15).
-- replaceAccountCopy: the unpublished build 1.33 created "SCB Polymorph" account-wide;
-- that copy is replaced by the character macro. No other macro of this addon ever existed
-- account-wide.
local function CreateOrUpdate(name, body, replaceAccountCopy)
    if InCombatLockdown() then ns.Print(L.NOT_IN_COMBAT) return end
    local maxAccount = MAX_ACCOUNT_MACROS or 120
    local index = CharacterMacroIndex(name, maxAccount)
    if index then
        EditMacro(index, name, MACRO_ICON, body)
        ns.Print(L.MACRO_UPDATED:format(name))
        return
    end
    local _, characterMacros = GetNumMacros()
    if characterMacros >= (MAX_CHARACTER_MACROS or 18) then
        ns.Print(L.MACRO_FULL)
        return
    end
    local accountIndex = GetMacroIndexByName(name)
    if replaceAccountCopy and accountIndex and accountIndex > 0 and accountIndex <= maxAccount then
        DeleteMacro(accountIndex)
    end
    -- 4th argument true = character macro
    CreateMacro(name, MACRO_ICON, body, true)
    ns.Print(L.MACRO_CREATED:format(name))
end

function ns.CreatePolymorphMacro()
    CreateOrUpdate(MACRO_NAME, MacroBody(), true)
end

-- The macro window's name field holds 16 characters. CreateMacro itself stores longer names
-- uncut (checked on build 1.60.1.70450), so a name kept within 16 survives being edited there.
local MACRO_NAME_MAX = 16

-- "SCB " plus the client's spell name, cut to the limit. Counted in UTF-8 characters, not
-- bytes: string.sub would split a Cyrillic or Chinese character in two.
local function SpellMacroName(spellId)
    local chars = {}
    for ch in ("SCB " .. ns.SpellName(spellId)):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #chars == MACRO_NAME_MAX then break end
        chars[#chars + 1] = ch
    end
    return table.concat(chars)
end

-- First press: Ice Block. A press inside the block ends it (/cancelaura runs first and
-- the cast then fails on the cooldown).
function ns.CreateIceBlockMacro()
    local spell = ns.SpellName(D.SPELL_ICE_BLOCK)
    if not spell then return end
    CreateOrUpdate(SpellMacroName(D.SPELL_ICE_BLOCK), table.concat({
        "#showtooltip " .. spell,
        "/cancelaura " .. spell,
        "/cast " .. spell,
    }, "\n"))
end

-- Drops the cast in progress and casts the spell at once. Counterspell aims at the focus
-- first, which the Polymorph macro sets. spellId defaults to the one chosen in the Macros tab.
function ns.CreateStopcastMacro(spellId)
    spellId = spellId or db.macroStopcast
    local spell = ns.SpellName(spellId)
    if not spell then return end
    local target = (spellId == D.SPELL_COUNTERSPELL) and "[@focus,harm,nodead][] " or ""
    CreateOrUpdate(SpellMacroName(spellId), table.concat({
        "#showtooltip " .. spell,
        "/stopcasting",
        "/cast " .. target .. spell,
    }, "\n"))
end
