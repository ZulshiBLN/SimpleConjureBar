-- SimpleConjureBar - entry points: minimap button, AddOn compartment, WoW options panel
-- Minimap button in Blizzard style (no library): left click = settings, right click = lock,
-- drag = move around the minimap.

local _, ns = ...
if not ns.enabled then return end

local D, L = ns.D, ns.L
local SetL = ns.SetL

local db
ns.OnDBReady(function(d) db = d end)

-- The right click names what it locks: here, away from the bar, "Lock" alone said nothing
local function ShowEntryTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:SetText("SimpleConjureBar |cffffffffv" .. ns.VERSION .. "|r")
    -- Single click lines, in combat only what works there: the lock, and the minimap button's
    -- drag (ruleset plan 2026-10-25-chat-and-docked-report)
    GameTooltip:AddLine(" ")
    if not InCombatLockdown() then GameTooltip:AddLine(L.HINT_LEFT:format(L.SETTINGS), 0, 1, 0) end
    GameTooltip:AddLine(L.HINT_RIGHT:format(db.locked and L.UNLOCK_BAR or L.LOCK_BAR), 0, 1, 0)
    if anchor == "ANCHOR_LEFT" then GameTooltip:AddLine(L.HINT_DRAG:format(L.MOVE), 0, 1, 0) end
    GameTooltip:Show()
end

-- owner, anchor: a tooltip the click came from, shown again so it says the new state at once -
-- the only answer: the chat speaks for commands only (ruleset plan 2026-10-25-chat-and-docked-report)
local function ToggleLockAndRedraw(owner, anchor)
    ns.ToggleLock()
    if owner and GameTooltip:IsOwned(owner) then ShowEntryTooltip(owner, anchor) end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local minimapBtn = CreateFrame("Button", "SimpleConjureBarMinimapButton", Minimap)
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

do
    local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(D.ADDON_ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = minimapBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
end

-- Position on a circle around the minimap
local function PlaceMinimapButton()
    local angle = math.rad(db and db.minimapAngle or D.VALUE_DEFAULTS.minimapAngle)
    local radius = (Minimap:GetWidth() / 2) + 10
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.ApplyMinimapButton()
    if db.hideMinimap then minimapBtn:Hide() else minimapBtn:Show() end
    PlaceMinimapButton()
end

local function OnMinimapDrag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    PlaceMinimapButton()
end
minimapBtn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnMinimapDrag) end)
minimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

minimapBtn:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then ToggleLockAndRedraw(self, "ANCHOR_LEFT") else ns.ToggleSettings() end
end)
minimapBtn:SetScript("OnEnter", function(self) ShowEntryTooltip(self, "ANCHOR_LEFT") end)
minimapBtn:SetScript("OnLeave", GameTooltip_Hide)

-- "Settings" key (Bindings.xml): a plain hidden button. The window refuses to open in combat
-- itself (Settings.lua), with its message.
local settingsKey = CreateFrame("Button", "SimpleConjureBarSettingsKey", UIParent)
settingsKey:Hide()
settingsKey:RegisterForClicks("AnyUp")
settingsKey:SetScript("OnClick", function() ns.ToggleSettings() end)

---------------------------------------------------------------------------
-- AddOn compartment (Retail addon menu next to the minimap). The globals the TOC names
-- live in Core.lua, ahead of the mage check, and call these.
---------------------------------------------------------------------------
-- The client passes the click no frame, so the entry the mouse entered redraws its tooltip
local menuEntry
function ns.CompartmentClick(_, button, menuButton)
    if button == "RightButton" then
        ToggleLockAndRedraw(menuButton or menuEntry, "ANCHOR_RIGHT")
    else
        ns.ToggleSettings()
    end
end

function ns.CompartmentEnter(_, menuButton)
    menuEntry = menuButton
    ShowEntryTooltip(menuButton, "ANCHOR_RIGHT")
end

function ns.CompartmentLeave()
    GameTooltip_Hide()
end

---------------------------------------------------------------------------
-- Entry in the WoW options (Options > AddOns): a page with a button that opens our window
---------------------------------------------------------------------------
function ns.RegisterOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "SimpleConjureBar"

    -- Everything centered: big gold title, version, chat command hints, button
    local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ns.SetLatinFont(head, GameFontNormalHuge, 36, "") -- "SimpleConjureBar" only
    head:SetTextColor(1, 0.82, 0) -- Blizzard gold
    head:SetPoint("TOP", panel, "TOP", 0, -120)
    head:SetText("SimpleConjureBar")

    local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ver:SetPoint("TOP", head, "BOTTOM", 0, -10)
    SetL(ver, "VERSION", ns.VERSION)

    local helpHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpHint:SetPoint("TOP", ver, "BOTTOM", 0, -18)
    SetL(helpHint, "HELP_HINT", "|cffffd100/scb help|r")

    local access = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    access:SetPoint("TOP", helpHint, "BOTTOM", 0, -6)
    SetL(access, "ACCESS_OPTIONS", "|cffffd100/scb|r")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    SetL(open, "OPEN_SETTINGS")
    local function FitOpen()
        open:SetSize(math.max(160, open:GetFontString():GetStringWidth() + 40), 28)
    end
    FitOpen()
    ns.OnLanguageChanged(FitOpen)
    open:SetPoint("TOP", access, "BOTTOM", 0, -18)
    open:SetScript("OnClick", function()
        -- The Blizzard window is not touched (closing it from addon code risks taint);
        -- our window opens above it instead
        ns.OpenSettings(true)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "SimpleConjureBar")
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category -- for Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end
