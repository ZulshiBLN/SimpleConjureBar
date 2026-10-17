-- SimpleConjureBar - macro helper
-- Creates the character macro "SCB Polymorph" (or updates it when it already exists).
--   First click without focus: the hostile, living target becomes the focus and gets the raid
--   marker chosen in the Macros tab (default: moon). Further clicks: Polymorph on the focus. A dead focus is cleared automatically.
-- /tm is used for the marker: SetRaidTarget is protected and cannot be called from /run.

local _, ns = ...
if not ns.enabled then return end

local D, L = ns.D, ns.L

local db
ns.OnDBReady(function(d) db = d end)

local MACRO_NAME = "SCB Polymorph"
local MACRO_ICON = "INV_MISC_QUESTIONMARK" -- #showtooltip shows the spell icon instead
local SPELL_POLYMORPH = 118                -- rank 1; the name is the same for every rank

local function MacroBody()
    -- The spell name must match the client language, so it comes from the client
    local spell = ns.SpellName(SPELL_POLYMORPH) or "Polymorph"
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
    -- Tab 2 = character macros (method names differ between client versions)
    if MacroFrame then
        if MacroFrame.SelectTab then
            pcall(MacroFrame.SelectTab, MacroFrame, 2)
        elseif MacroFrameTab2 and MacroFrameTab2.Click then
            MacroFrameTab2:Click()
        end
    end
    ns.CloseSettings() -- our window would cover the macro window
end

function ns.CreatePolymorphMacro()
    if InCombatLockdown() then ns.Print(L.NOT_IN_COMBAT) return end
    local body = MacroBody()
    local maxAccount = MAX_ACCOUNT_MACROS or 120
    local index = GetMacroIndexByName(MACRO_NAME)
    if index and index > maxAccount then
        -- Character macros use the indexes after the account-wide ones
        EditMacro(index, MACRO_NAME, MACRO_ICON, body)
        ns.Print(L.MACRO_UPDATED:format(MACRO_NAME))
        return
    end
    local _, characterMacros = GetNumMacros()
    if characterMacros >= (MAX_CHARACTER_MACROS or 18) then
        ns.Print(L.MACRO_FULL)
        return
    end
    -- Version 1.33 created the macro account-wide: that copy is replaced by the character macro
    if index and index > 0 then DeleteMacro(index) end
    -- 4th argument true = character macro
    CreateMacro(MACRO_NAME, MACRO_ICON, body, true)
    ns.Print(L.MACRO_CREATED:format(MACRO_NAME))
end
