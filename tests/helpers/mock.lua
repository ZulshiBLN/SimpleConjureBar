-- Minimal WoW API mock for smoke tests
local noop = function() end
local objects = {}
local eventFrames = {}
local timers = {}
STATE = { combat = false, group = false, raid = false, members = 0, locale = "deDE", errors = {} }

local Methods = {}
local function New(kind, name, parent)
  local o = { kind = kind, name = name, parent = parent, shown = true, attrs = {}, scripts = {}, hooks = {},
              regions = {}, children = {}, text = nil, w = 100, h = 20, events = {} }
  if kind == "Frame" or kind == "Button" or kind == "CheckButton" or kind == "Slider" or kind == "EditBox"
     or kind == "Cooldown" or kind == "DropdownButton" then o.isFrame = true end
  setmetatable(o, { __index = function(t, k) if Methods[k] then return Methods[k] end if type(k) == "string" and k:match("^%u") then return noop end end })
  if parent then
    if o.isFrame then table.insert(parent.children, o) else table.insert(parent.regions, o) end
  end
  objects[#objects + 1] = o
  return o
end
NEWOBJ = New
local function Run(o, script, ...)
  local f = o.scripts[script]
  if f then local ok, err = pcall(f, o, ...); if not ok then table.insert(STATE.errors, script .. ": " .. tostring(err)) end end
  for _, h in ipairs(o.hooks[script] or {}) do
    local ok, err = pcall(h, o, ...); if not ok then table.insert(STATE.errors, script .. " hook: " .. tostring(err)) end
  end
end
RUNSCRIPT = Run
function Methods:SetText(t) self.text = t; if self.isFrame then self:GetFontString().text = t end end
function Methods:GetText() return self.text end
function Methods:GetStringWidth() return #(tostring(self.text or "")) * 7 end
function Methods:Show() if not self.shown then self.shown = true; Run(self, "OnShow") end end
function Methods:Hide() if self.shown then self.shown = false; Run(self, "OnHide") end end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown end
function Methods:SetAttribute(k, v) self.attrs[k] = v; self.attrWrites = (self.attrWrites or 0) + 1 end
function Methods:GetAttribute(k) return self.attrs[k] end
function Methods:SetScript(s, f) self.scripts[s] = f end
function Methods:GetScript(s) return self.scripts[s] end
function Methods:HookScript(s, f) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], f) end
function Methods:CreateFontString(n) return New("FontString", n, self) end
function Methods:CreateTexture(n) return New("Texture", n, self) end
function Methods:CreateAnimationGroup() return New("AnimationGroup", nil, nil) end
function Methods:GetFontString() if not self.fs then self.fs = New("FontString", nil, self) end return self.fs end
function Methods:GetRegions() return unpack(self.regions) end
function Methods:GetChildren() return unpack(self.children) end
function Methods:GetRect() return 100, 100, self.w, self.h end
function Methods:GetCenter() return 500, 300 end
function Methods:GetWidth() return self.w end
function Methods:GetHeight() return self.h end
function Methods:SetWidth(w) self.w = w end
function Methods:SetHeight(h) self.h = h end
function Methods:SetSize(w, h) self.w, self.h = w, h end
function Methods:GetScale() return self.scale or 1 end
function Methods:SetScale(s) if STATE.combat and self.protected then error("protected SetScale in combat") end self.scale = s end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetName() return self.name end
function Methods:GetParent() return self.parent end
function Methods:SetParent(p) self.parent = p end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Methods:GetFontObjectForAlphabet() return self end
function Methods:GetBackdrop() return {} end
function Methods:IsMouseOver() return false end
function Methods:GetTop() return 400 end
function Methods:GetPushedTexture() return New("Texture", nil, self) end
function Methods:GetHighlightTexture() return New("Texture", nil, self) end
function Methods:GetChecked() return self.checked end
function Methods:SetChecked(v) self.checked = v end
function Methods:GetValue() return self.value or 0 end
function Methods:SetValue(v) self.value = v; Run(self, "OnValueChanged", v) end
function Methods:RegisterEvent(e) self.events[e] = true; eventFrames[self] = true end
function Methods:UnregisterEvent(e) self.events[e] = nil end
function Methods:GetObjectType() return self.kind end
function Methods:SetupMenu(f) self.menuFn = f end
function Methods:Cancel() self.cancelled = true end
function Methods:GetColorRGB() return 1, 1, 1 end
function Methods:GetFrameLevel() return 1 end

function CreateFrame(kind, name, parent, template)
  local o = New(kind, name, parent)
  o.template = template
  if template and template:find("Secure") then o.protected = true end
  if name then _G[name] = o end
  o.shown = true
  return o
end
function FIRE(event, ...)
  for f in pairs(eventFrames) do
    if f.events[event] then Run(f, "OnEvent", event, ...) end
  end
end
function RUNTIMERS()
  local n = 0
  while #timers > 0 and n < 50 do
    local list = timers; timers = {}
    for _, t in ipairs(list) do local ok, err = pcall(t); if not ok then table.insert(STATE.errors, "timer: " .. err) end end
    n = n + 1
  end
end
TICKERS = {}
C_Timer = {
  After = function(_, f) table.insert(timers, f) end,
  NewTicker = function(_, f) local t = New("Ticker"); t.fn = f; TICKERS[#TICKERS + 1] = t; return t end,
}
function TICK() for _, t in ipairs(TICKERS) do if not t.cancelled then local ok, e = pcall(t.fn); if not ok then table.insert(STATE.errors, "ticker: "..e) end end end end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
GameTooltip = CreateFrame("Frame", "GameTooltip")
ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame")
for _, n in ipairs({ "GameFontNormal", "GameFontNormalHuge", "GameFontHighlightSmall", "NumberFontNormal", "GameFontNormalLarge" }) do
  _G[n] = New("Font", n)
end
CreateFontFamily = function(name, members)
  assert(type(name) == "string" and #members > 0, "bad font family")
  for _, m in ipairs(members) do assert(m.alphabet and m.file and m.height, "bad member") end
  local f = New("Font", name); _G[name] = f; return f
end
UISpecialFrames = {}
BackdropTemplateMixin = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GameTooltip_Hide = noop
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end CHAT[#CHAT+1] = table.concat(t, " ") end
CHAT = {}
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
PixelUtil = { SetSize = function(t, w, h) t:SetSize(w, h) end }
Settings = { RegisterCanvasLayoutCategory = function(p, n) return { GetID = function() return 1 end } end, RegisterAddOnCategory = noop }
RegisterStateDriver = noop; UnregisterStateDriver = noop
InCombatLockdown = function() return STATE.combat end
IsInGroup = function() return STATE.group end
IsInRaid = function() return STATE.raid end
GetNumGroupMembers = function() return STATE.members end
GetNumSubgroupMembers = function() return STATE.raid and 4 or (STATE.group and STATE.members - 1 or 0) end
GetRaidRosterInfo = function(i) return "n"..i, 0, math.floor((i - 1) / 5) + 1 end
UnitClass = function(u) return "Mage", "MAGE" end
UnitFactionGroup = function() return "Horde" end
UnitExists = function(u) return u ~= "target" or STATE.target end
UnitIsPlayer = function() return true end
UnitIsUnit = function(a, b) return a == b end
UnitIsFriend = function() return true end
UnitLevel = function() return 60 end
UnitName = function(u) if u == "NPC" then return STATE.tradePartner end return "Name_" .. u end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitIsVisible = function() return true end
UnitInRange = function() return true end
GetLocale = function() return STATE.locale end
GetMoney = function() return 1000000 end
GetMerchantNumItems = function() return STATE.merchantItems or 0 end
GetMerchantItemID = function(i) return ({17031, 17020, 1234})[i] end
GetMerchantItemMaxStack = function() return 20 end
GetMerchantItemInfo = function() return "x", "", 100, 1 end
BUYS = {}
BuyMerchantItem = function(i, n) BUYS[#BUYS+1] = {i, n} end
GetCursorPosition = function() return 0, 0 end
IsMouseButtonDown = function() return false end
GetCVar = function() return "1" end
GetTime = function() return 100 end
ReloadUI = noop
CheckInteractDistance = function() return true end
InitiateTrade = noop
-- Trade: what the cursor holds, and what each of our trade slots received.
-- A click on a slot moves the held bag item into it, as the client does.
CURSOR = nil
TRADE_SLOTS = {}
GetTradePlayerItemLink = function(i) return TRADE_SLOTS[i] and ("item:" .. TRADE_SLOTS[i]) or nil end
ClearCursor = function() CURSOR = nil end
ClickTradeButton = function(i) if CURSOR then TRADE_SLOTS[i] = CURSOR; CURSOR = nil end end
SlashCmdList = {}
NUM_BAG_SLOTS = 4
C_Spell = {
  GetSpellName = function(id) return "Spell" .. id end,
  GetSpellTexture = function(id) return id end,
  IsSpellInRange = function() return true end,
}
C_SpellBook = { IsSpellKnown = function(id) return id ~= 429307 end }
IsPlayerSpell = function() return false end
ITEMS = { [8079] = 20, [8076] = 20, [17031] = 3, [17020] = 5, [8008] = 1 }
C_Item = {
  GetItemCount = function(id) return ITEMS[id] or 0 end,
  GetItemIconByID = function(id) return id end,
  GetItemNameByID = function(id) return "Item" .. id end,
  GetItemInfo = function(id) return "Item"..id, nil, nil, nil, 55 end,
}
-- Bag 0 holds the best water and food the scenario owns; other bags are empty.
BAGS = { [0] = { { itemID = 8079, stackCount = 20 }, { itemID = 8076, stackCount = 20 } } }
C_Container = {
  GetItemCooldown = function() return 0, 0 end,
  GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
  PickupContainerItem = function(bag, slot) local s = BAGS[bag] and BAGS[bag][slot]; CURSOR = s and s.itemID end,
  GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
C_UnitAuras = { GetAuraDataBySpellName = function(u, name) if AURAS[u .. name] then return {} end end }
AURAS = {}
C_AddOns = { GetAddOnMetadata = function() return "1.27" end }
C_CurrencyInfo = { GetCoinTextureString = function(m) return m .. "c" end }
UIDropDownMenu_SetWidth = noop
UnitGUID = function(u) if u == "NPC" then return STATE.tradeGuid end return "Player-1-" .. u end
AURALIST = {}
C_UnitAuras.GetAuraDataByIndex = function(u, i) local l = AURALIST[u]; if l and l[i] then return { spellId = l[i], name = "A" .. l[i] } end end
MACROS = {}
GetMacroIndexByName = function(n) for i, m in ipairs(MACROS) do if m.name == n then return m.perChar and 120 + i or i end end return 0 end
GetNumMacros = function() local a,c=0,0 for _,m in ipairs(MACROS) do if m.perChar then c=c+1 else a=a+1 end end return a,c end
DeleteMacro = function(i) table.remove(MACROS, i) end
MAX_ACCOUNT_MACROS = 120
CreateMacro = function(n, icon, body, perChar) MACROS[#MACROS+1] = { name = n, body = body, perChar = perChar } return #MACROS end
EditMacro = function(i, n, icon, body) MACROS[i > 120 and i - 120 or i].body = body end
GetBuildInfo = function() return "1.15.0", "99999", "Oct 1 2026", 16001 end
date = os.date
BugGrabber = { GetDB = function() return {
  { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:10: attempt to index nil", stack = "[SimpleConjureBar/Bar.lua]:10\n[C]: ?", counter = 3, time = "2026/10/17 02:00" },
  { message = "OtherAddon error", stack = "[Other/x.lua]:1", counter = 1 } } end }
