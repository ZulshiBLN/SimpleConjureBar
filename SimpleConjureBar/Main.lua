-- SimpleConjureBar - startup and chat commands

local _, ns = ...
if not ns.enabled then return end

local L = ns.L
local Print = ns.Print

local db
ns.OnDBReady(function(d) db = d end)

-- Button texts depend on the language (armor labels, tooltip hints). At login the language
-- is applied before the bar is positioned, so no rebuild may run yet.
ns.OnLanguageChanged(function()
    if ns.barReady then ns.Rebuild() end
end)

local function PrintGreeting()
    print("|cff69ccf0SimpleConjureBar|r |cffffffffv" .. ns.VERSION .. "|r")
    print(L.HELP_HINT:format("|cffffd100/scb help|r"))
    print(L.ACCESS_OPTIONS:format("|cffffd100/scb|r"))
end

-- Scale, position and layout of the bar (protected while in combat)
local function SetupBar()
    ns.bar:SetScale(db.scale) -- before positioning: the position is stored in the scaled system
    ns.LoadPosition()
    ns.ApplyCombatHide()
    ns.barReady = true -- before the rebuild, which needs it (Buttons.lua)
    ns.Rebuild()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        SetupBar()
        return
    end
    local migrated = ns.InitDB()
    -- Saved language choice (account-wide), otherwise the client language. Applied before any
    -- chat output, so every message already uses the chosen language.
    local lang = SimpleConjureBarGlobalDB.language
    if lang and ns.locales[lang] then ns.ApplyLanguage(lang) end
    if migrated then Print(L.MIGRATED) end

    ns.ApplyLock()
    ns.ApplyLook()
    if InCombatLockdown() then
        -- /reload in combat: the bar holds secure buttons, so scale and position are set after combat
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        SetupBar()
    end
    ns.RegisterOptionsPanel()
    ns.ApplyMinimapButton()

    PrintGreeting()
end)

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
SLASH_SIMPLECONJUREBAR1 = "/scb"
SLASH_SIMPLECONJUREBAR2 = "/cbar" -- old command of "ConjureBar" keeps working

-- All commands with their description (order = output of /scb help)
local COMMANDS = {
    { cmd = "",        desc = "CMD_OPEN" },
    { cmd = "help",    desc = "CMD_HELP" },
    { cmd = "lock",    desc = "CMD_LOCK" },
    { cmd = "minimap", desc = "CMD_MINIMAP" },
    { cmd = "demo",    desc = "CMD_DEMO" },
    { cmd = "reset",   desc = "CMD_RESET" },
    { cmd = "bug",     desc = "CMD_BUG" },
    { cmd = "debug",   desc = "CMD_DEBUG" },
}

local function PrintHelp()
    Print("v" .. ns.VERSION .. " - " .. L.HELP_HEADER)
    for _, c in ipairs(COMMANDS) do
        local full = c.cmd == "" and "/scb" or ("/scb " .. c.cmd)
        print("   |cffffd100" .. full .. "|r - " .. L[c.desc])
    end
end

-- Technical output, deliberately not localized: the bug report's state snapshot (Report.lua)
local function PrintDebug()
    for _, line in ipairs(ns.StateSnapshot()) do Print(line) end
end

SlashCmdList.SIMPLECONJUREBAR = function(msg)
    if not db then return end
    msg = strtrim((msg or ""):lower())
    if msg == "" then
        ns.ToggleSettings()
    elseif msg == "help" or msg == "?" then
        PrintHelp()
    elseif msg == "lock" then
        ns.ToggleLock()
        Print(db.locked and L.LOCKED or L.UNLOCKED)
    elseif msg == "minimap" then
        db.hideMinimap = not db.hideMinimap
        ns.ApplyMinimapButton()
        ns.RefreshSettingsWindow()
        Print(db.hideMinimap and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
    elseif msg == "demo" then
        -- the buttons' actions change only after combat; the switch would come before them
        if InCombatLockdown() then Print(L.NOT_IN_COMBAT) return end
        db.demo = not db.demo
        ns.Rebuild()
        ns.ApplyLook()
        ns.RefreshSettingsWindow()
        Print(db.demo and L.DEMO_ON or L.DEMO_OFF)
    elseif msg == "reset" then
        if InCombatLockdown() then Print(L.NOT_IN_COMBAT) return end
        db.point, db.rel, db.x, db.y = nil, nil, nil, nil
        ns.LoadPosition()
        ns.Rebuild() -- re-anchor at the anchor point
        Print(L.POS_RESET)
    elseif msg == "bug" then
        ns.OpenBugReport()
    elseif msg == "debug" then
        PrintDebug()
    else
        Print(L.CMD_UNKNOWN:format("|cffffd100/scb help|r"))
    end
    ns.LogSettings() -- lock, minimap and demo change settings outside the window
end
