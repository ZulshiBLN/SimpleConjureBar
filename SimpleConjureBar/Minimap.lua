-- SimpleConjureBar - entry points: minimap button, AddOn compartment, WoW options panel
-- Minimap button in Blizzard style (no library): left click = settings, right click = lock,
-- drag = move around the minimap.

local _, ns = ...
if not ns.enabled then return end

local D, L = ns.D, ns.L
local SetL = ns.SetL

local db
ns.OnDBReady(function(d) db = d end)

local function ToggleLockWithMessage()
    ns.ToggleLock()
    ns.Print(db.locked and L.LOCKED or L.UNLOCKED)
end

local function ShowEntryTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:SetText("SimpleConjureBar |cffffffffv" .. ns.VERSION .. "|r")
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.LEFTCLICK, L.SETTINGS, 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.RIGHTCLICK, db.locked and L.UNLOCK or L.LOCK, 0, 1, 0, 1, 1, 1)
    if anchor == "ANCHOR_LEFT" then
        GameTooltip:AddDoubleLine(L.DRAG, L.MOVE, 0, 1, 0, 1, 1, 1)
    end
    GameTooltip:Show()
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

minimapBtn:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then ToggleLockWithMessage() else ns.ToggleSettings() end
end)
minimapBtn:SetScript("OnEnter", function(self) ShowEntryTooltip(self, "ANCHOR_LEFT") end)
minimapBtn:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- AddOn compartment (Retail addon menu next to the minimap). The TOC points to these
-- globals, which is why they are deliberately global.
---------------------------------------------------------------------------
function SimpleConjureBar_OnCompartmentClick(_, button)
    if button == "RightButton" then ToggleLockWithMessage() else ns.ToggleSettings() end
end

function SimpleConjureBar_OnCompartmentEnter(_, menuButton)
    ShowEntryTooltip(menuButton, "ANCHOR_RIGHT")
end

function SimpleConjureBar_OnCompartmentLeave()
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
