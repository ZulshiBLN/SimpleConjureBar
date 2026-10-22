-- Minimal WoW API mock for smoke tests
local noop = function() end
local objects = {}
-- Frames get events in the order they first registered: a fixed order, so a spec can rely on
-- one; this one puts the settings window (made at load) before the report (made on demand)
local eventFrames, eventOrder = {}, {}
local timers = {}
STATE = { combat = false, group = false, raid = false, members = 0, locale = "deDE", errors = {}, casts = {},
          units = {}, friends = {}, targetedNext = 0, cooldowns = {}, secret = false, now = 100 }

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
-- In combat the client refuses an addon's write to a protected frame (ADDON_ACTION_BLOCKED):
-- recorded as an error and not written. Secure snippets write through their handles instead.
function Methods:SetAttribute(k, v)
  if STATE.combat and self.protected then
    table.insert(STATE.errors, ("BLOCKED SetAttribute %s %s"):format(tostring(self.name), tostring(k)))
    return
  end
  self.attrs[k] = v; self.attrWrites = (self.attrWrites or 0) + 1
end
function Methods:GetAttribute(k) return self.attrs[k] end
function Methods:SetScript(s, f) self.scripts[s] = f end
function Methods:GetScript(s) return self.scripts[s] end
function Methods:HookScript(s, f) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], f) end
function Methods:CreateFontString(n) return New("FontString", n, self) end
function Methods:CreateTexture(n, layer, _, sublevel)
  local t = New("Texture", n, self)
  t.layer, t.sublevel = layer, sublevel
  return t
end
function Methods:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
-- BackdropTemplate: SetBackdrop makes the centre piece the background is drawn on, in
-- BACKGROUND; the colours are recorded
function Methods:SetBackdrop(b)
  self.backdrop = b
  if not rawget(self, "Center") then
    self.Center = New("Texture", nil, self)
    self.Center.layer, self.Center.sublevel = "BACKGROUND", -8
  end
end
function Methods:GetBackdrop() return self.backdrop end
function Methods:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function Methods:SetBackdropBorderColor(r, g, b, a) self.borderColor = { r, g, b, a } end
-- Animation groups as the client's: they record their animations, looping and play state;
-- the client plays them, a spec reads what was set
function Methods:CreateAnimationGroup()
  local group = { animations = {}, playing = false }
  group.SetLooping = function(g, v) g.looping = v end
  group.Play = function(g) g.playing = true end
  group.Stop = function(g) g.playing = false end
  group.IsPlaying = function(g) return g.playing end
  group.CreateAnimation = function(g, kind)
    local a = { kind = kind }
    a.SetFlipBookRows = function(x, n) x.rows = n end
    a.SetFlipBookColumns = function(x, n) x.columns = n end
    a.SetFlipBookFrames = function(x, n) x.frames = n end
    a.SetDuration = function(x, s) x.duration = s end
    a.GetDuration = function(x) return x.duration end
    table.insert(g.animations, a)
    return a
  end
  return group
end
function Methods:SetAtlas(a) self.atlas = a end
function Methods:SetDesaturated(v) self.desaturated = v and true or false end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:GetAlpha() return self.alpha or 1 end
function Methods:SetTexture(t) self.texture = t end
function Methods:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
-- The anchors a region was last given, in order (ClearAllPoints empties them)
function Methods:SetPoint(...) self.points = rawget(self, "points") or {}; table.insert(self.points, { ... }) end
function Methods:ClearAllPoints() self.points = {} end
function Methods:GetPoint(i) local p = (rawget(self, "points") or {})[i or 1]; if p then return unpack(p) end end
function Methods:GetFontString() if not self.fs then self.fs = New("FontString", nil, self) end return self.fs end
function Methods:GetRegions() return unpack(self.regions) end
function Methods:GetChildren() return unpack(self.children) end
-- The rect follows the frame's last anchor on UIParent (a 2000 x 650 screen), so a saved
-- position can be told from the start position; other anchors give a fixed rect
local ANCHOR = { CENTER = { 0.5, 0.5 }, LEFT = { 0, 0.5 }, RIGHT = { 1, 0.5 }, TOP = { 0.5, 1 },
  BOTTOM = { 0.5, 0 }, BOTTOMLEFT = { 0, 0 }, BOTTOMRIGHT = { 1, 0 }, TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 } }
function Methods:GetRect()
  local points = rawget(self, "points") or {}
  local last = points[#points]
  if not last or last[2] ~= UIParent then return 100, 100, self.w, self.h end
  local point, _, rel, x, y = unpack(last)
  local a, r = ANCHOR[point], ANCHOR[rel or point]
  if not a or not r then return 100, 100, self.w, self.h end
  local ax, ay = UIParent.w * r[1] + (x or 0), UIParent.h * r[2] + (y or 0)
  return ax - self.w * a[1], ay - self.h * a[2], self.w, self.h
end
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
function Methods:IsMouseOver() return false end
function Methods:GetTop() return 400 end
function Methods:GetPushedTexture() return New("Texture", nil, self) end
function Methods:GetHighlightTexture() return New("Texture", nil, self) end
-- An edit box's selection: "all" for HighlightText(), "none" for HighlightText(0, 0); focus
-- runs OnEditFocusGained, as in the client
function Methods:HighlightText(a, b) self.selection = (a == nil and b == nil) and "all" or (a == b and "none" or "part") end
function Methods:SetFocus() self.focused = true; Run(self, "OnEditFocusGained") end
function Methods:ClearFocus() self.focused = false end
function Methods:GetChecked() return self.checked end
function Methods:SetChecked(v) self.checked = v end
function Methods:GetValue() return self.value or 0 end
function Methods:SetValue(v) self.value = v; Run(self, "OnValueChanged", v) end
function Methods:RegisterEvent(e)
  self.events[e] = true
  if not eventFrames[self] then eventFrames[self] = true; eventOrder[#eventOrder + 1] = self end
end
function Methods:UnregisterEvent(e) self.events[e] = nil end
function Methods:GetObjectType() return self.kind end
-- A menu dropdown shows the text of its selected radio; the client takes it when the menu is
-- generated - at SetupMenu and at GenerateMenu - not when a text changes later
function Methods:GenerateMenu()
  if not self.menuFn then return end
  self.selectedText = nil
  self.menuFn(self, { CreateRadio = function(_, text, isSelected)
    if isSelected and isSelected() then self.selectedText = text end
  end })
end
function Methods:SetupMenu(f) self.menuFn = f; self:GenerateMenu() end
function Methods:Cancel() self.cancelled = true end
function Methods:GetColorRGB() return 1, 1, 1 end
function Methods:GetFrameLevel() return 1 end

function Methods:SetRotation(r) self.rotation = r end

---------------------------------------------------------------------------
-- Secure snippets, as in SmartBlessingBar's mock. A SecureHandler header wraps a frame's
-- OnClick with a pre and a post body, as WrapScript does. The bodies run in an emulated
-- restricted environment and see frames only through handles. Bodies are compiled with
-- their arguments as locals, like the client's.
---------------------------------------------------------------------------
local handles = setmetatable({}, { __mode = "k" })
local framesOf = setmetatable({}, { __mode = "k" })
local function Handle(frame)
  if not frame then return nil end
  if handles[frame] then return handles[frame] end
  local h = {}
  framesOf[h] = frame
  -- The client's secure auto-hide: recorded as the frame's autoHide seconds and the frames
  -- that keep it open (autoHideWith). Like the client it works only on a protected frame.
  function h:RegisterAutoHide(seconds)
    if not frame.protected then error("RegisterAutoHide on an unprotected frame") end
    frame.autoHide = seconds
    frame.autoHideWith = {}
  end
  function h:AddToAutoHide(other)
    if not frame.autoHide then error("AddToAutoHide before RegisterAutoHide") end
    table.insert(frame.autoHideWith, framesOf[other])
  end
  function h:UnregisterAutoHide() frame.autoHide = nil; frame.autoHideWith = nil end
  function h:GetAttribute(k) return frame.attrs[k] end
  function h:SetAttribute(k, v) frame.attrs[k] = v end
  function h:Show() frame.shown = true end
  function h:Hide() frame.shown = false end
  function h:IsShown() return frame.shown end
  function h:GetParent() return Handle(frame.parent) end
  function h:GetName() return frame.name end
  function h:GetFrameRef(name) return Handle(frame.refs and frame.refs[name]) end
  -- In combat the client refuses a handle to a frame that is not protected
  for name, fn in pairs(h) do
    h[name] = function(...)
      if STATE.combat and not frame.protected then error("Invalid frame handle") end
      return fn(...)
    end
  end
  handles[frame] = h
  return h
end

local restricted = {
  PlayerInCombat = function() return STATE.combat end,
  newtable = function(...) return { ... } end,
  pairs = pairs, ipairs = ipairs, tostring = tostring, type = type,
}
local function Compile(body, args)
  local chunk = assert(loadstring("local " .. args .. " = ...\n" .. body))
  setfenv(chunk, setmetatable({}, { __index = restricted }))
  return chunk
end

function Methods:SetFrameRef(name, frame)
  self.refs = self.refs or {}
  self.refs[name] = frame
end
function Methods:WrapScript(frame, script, pre, post)
  frame.wraps = frame.wraps or {}
  frame.wraps[script] = frame.wraps[script] or {}
  table.insert(frame.wraps[script], {
    owner = self,
    pre = pre and Compile(pre, "self, button, down, owner"),
    post = post and Compile(post, "self, message, button, down, owner"),
  })
end

-- A click as the client delivers it to a secure button: PreClick, the wrappers' pre bodies
-- (false cancels the action and every post body), the secure action (on key down while
-- STATE.keyDown, else on key up; a macro's "/click ... 1" acts in both, as the client's did -
-- ruleset plan 2026-10-21-buff-and-run), the post bodies of the wrappers that returned a
-- message, then the insecure scripts - none of them after a cancel: the client's OnClick
-- never runs for a click a snippet dropped (ruleset decisions, 2026-10-21). A spell cast is appended to STATE.casts as
-- { spell, unit }; a macro runs its "/click Name [button] [1]" and "/targetfriendplayer"
-- lines, the latter making the next of STATE.friends the target and counting in
-- STATE.targetedNext.
local function Attr(frame, name, button)
  local suffix = button == "LeftButton" and "1" or button == "RightButton" and "2"
    or button == "MiddleButton" and "3" or ""
  local v = frame.attrs[name .. suffix]
  if v == nil then v = frame.attrs[name] end
  return v
end
local RunMacro
function RUNCLICK(frame, button, down, fromMacro)
  Run(frame, "PreClick", button, down)
  local cancelled, messages = false, {}
  local wraps = frame.wraps and frame.wraps.OnClick or {}
  for i, w in ipairs(wraps) do
    if w.pre then
      local ok, result, message = pcall(w.pre, Handle(frame), button, down, Handle(w.owner))
      if not ok then table.insert(STATE.errors, "snippet: " .. tostring(result)) end
      if result == false then cancelled = true break end
      messages[i] = message
    end
  end
  if not cancelled then
    if frame.template and frame.template:find("SecureActionButtonTemplate")
       and (fromMacro or (down == true) == (STATE.keyDown == true)) then
      local kind = Attr(frame, "type", button)
      if kind == "spell" and Attr(frame, "spell", button) ~= nil then
        STATE.casts[#STATE.casts + 1] = { spell = Attr(frame, "spell", button), unit = Attr(frame, "unit", button) }
      elseif kind == "macro" then
        RunMacro(Attr(frame, "macrotext", button))
      end
    end
    for i, w in ipairs(wraps) do
      if w.post and messages[i] ~= nil then
        local ok, err = pcall(w.post, Handle(frame), messages[i], button, down, Handle(w.owner))
        if not ok then table.insert(STATE.errors, "snippet: " .. tostring(err)) end
      end
    end
    Run(frame, "OnClick", button, down)
  end
end
RunMacro = function(text)
  for line in (text or ""):gmatch("[^\n]+") do
    local name, mouse, keyDown = line:match("^/click%s+(%S+)%s*(%S*)%s*(%S*)")
    if name then
      local target = _G[name]
      if target then RUNCLICK(target, mouse ~= "" and mouse or "LeftButton", keyDown == "1", true) end
    elseif line:match("^/targetfriendplayer") then
      STATE.units.target = table.remove(STATE.friends, 1)
      STATE.targetedNext = STATE.targetedNext + 1
    end
  end
end

function CreateFrame(kind, name, parent, template)
  local o = New(kind, name, parent)
  o.template = template
  if template and template:find("Secure") then
    o.protected = true
    -- A frame holding a secure button is protected too, as in the client
    if parent then parent.protected = true end
  end
  -- The menu dropdown template carries its selection text in .Text
  if template == "WowStyle1DropdownTemplate" then o.Text = New("FontString", nil, o) end
  if name then _G[name] = o end
  o.shown = true
  return o
end
function FIRE(event, ...)
  for _, f in ipairs(eventOrder) do
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
-- NewTimer keeps its delay and waits for ADVANCE: RUNTIMERS would fire it at once, and with the
-- clock standing still a timer that re-arms itself would run 50 rounds.
DELAYED = {} -- timers waiting for ADVANCE, visible to specs
C_Timer = {
  After = function(_, f) table.insert(timers, f) end,
  NewTicker = function(_, f) local t = New("Ticker"); t.fn = f; TICKERS[#TICKERS + 1] = t; return t end,
  NewTimer = function(delay, f)
    local t = { delay = delay, due = GetTime() + delay, fn = f, cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    DELAYED[#DELAYED + 1] = t
    return t
  end,
}
-- Moves the clock and runs the timers now due, earliest first
function ADVANCE(seconds)
  STATE.now = STATE.now + seconds
  for round = 1, 100 do -- a timer re-arming itself at the same moment would loop forever
    if round == 100 then table.insert(STATE.errors, "ADVANCE: timers keep re-arming") break end
    local nextT, at
    for i, t in ipairs(DELAYED) do
      if not t.cancelled and t.due <= STATE.now and (not nextT or t.due < DELAYED[at].due) then nextT, at = t, i end
    end
    if not nextT then break end
    table.remove(DELAYED, at)
    local ok, err = pcall(nextT.fn)
    if not ok then table.insert(STATE.errors, "timer: " .. err) end
  end
end
function TICK() for _, t in ipairs(TICKERS) do if not t.cancelled then local ok, e = pcall(t.fn); if not ok then table.insert(STATE.errors, "ticker: "..e) end end end end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(2000, 650)
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
-- The tooltip remembers its owner, as the client's does
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:IsOwned(frame) return self.owner == frame end
GameTooltip_Hide = function() GameTooltip.owner = nil end
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end CHAT[#CHAT+1] = table.concat(t, " ") end
CHAT = {}
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
PixelUtil = { SetSize = function(t, w, h) t:SetSize(w, h) end }
Settings = { RegisterCanvasLayoutCategory = function(p, n) return { GetID = function() return 1 end } end, RegisterAddOnCategory = noop }
-- A state driver is recorded on its frame as { state, value }; in combat the client refuses
-- both calls, as it does SetAttribute
RegisterStateDriver = function(f, state, value)
  if STATE.combat then table.insert(STATE.errors, "BLOCKED RegisterStateDriver " .. tostring(f.name)) return end
  f.stateDriver = { state, value }
end
UnregisterStateDriver = function(f)
  if STATE.combat then table.insert(STATE.errors, "BLOCKED UnregisterStateDriver " .. tostring(f.name)) return end
  f.stateDriver = nil
end
InCombatLockdown = function() return STATE.combat end
UnitAffectingCombat = function() return STATE.affecting == true or STATE.combat == true end
IsInGroup = function() return STATE.group end
IsInRaid = function() return STATE.raid end
GetNumGroupMembers = function() return STATE.members end
GetNumSubgroupMembers = function() return STATE.raid and 4 or (STATE.group and STATE.members - 1 or 0) end
GetRaidRosterInfo = function(i) return "n"..i, 0, math.floor((i - 1) / 5) + 1 end
-- A unit a spec describes in STATE.units[token] (class, level, player, assist, pvp, dead,
-- connected, range, name, auras = { spell IDs }); every other unit answers the defaults,
-- a level 60 mage in reach
local function U(u) return STATE.units[u] end
UnitClass = function(u) local r = U(u) if r and r.class then return r.class, r.class end return "Mage", "MAGE" end
UnitFactionGroup = function() return "Horde" end
UnitExists = function(u) if U(u) then return true end return u ~= "target" or STATE.target end
UnitIsPlayer = function(u) local r = U(u) return not r or r.player ~= false end
UnitCanAssist = function(_, u) local r = U(u) return not r or r.assist ~= false end
UnitIsPVP = function(u) local r = U(u) return r and r.pvp == true or false end
IsPVPTimerRunning = function() return STATE.pvpTimer == true end
-- A unit entry with `is = "player"` is the player under another token, as a self-target is
UnitIsUnit = function(a, b)
  local function Id(u) local r = STATE.units[u] return r and r.is or u end
  return Id(a) == Id(b)
end
UnitIsFriend = function() return true end
UnitLevel = function(u) local r = U(u) return r and r.level or 60 end
UnitName = function(u) if u == "NPC" then return STATE.tradePartner end local r = U(u) return r and r.name or "Name_" .. u end
UnitIsConnected = function(u) local r = U(u) return not r or r.connected ~= false end
UnitIsDeadOrGhost = function(u) local r = U(u) return r and r.dead == true or false end
UnitIsVisible = function() return true end
UnitInRange = function() return true end
C_Secrets = { ShouldAurasBeSecret = function() return STATE.secret end }
GetLocale = function() return STATE.locale end
GetRealmName = function() return "Realm" end
GetNormalizedRealmName = function() return "Realm" end
GetGuildInfo = function() return nil end
GetMoney = function() return 1000000 end
GetMerchantNumItems = function() return STATE.merchantItems or 0 end
GetMerchantItemID = function(i) return ({17031, 17020, 1234})[i] end
GetMerchantItemMaxStack = function() return 20 end
GetMerchantItemInfo = function() return "x", "", 100, 1 end
BUYS = {}
BuyMerchantItem = function(i, n) BUYS[#BUYS+1] = {i, n} end
GetCursorPosition = function() return 0, 0 end
IsMouseButtonDown = function() return false end
GetCVar = function(name)
  if name == "ActionButtonUseKeyDown" then return STATE.keyDown and "1" or "0" end
  return "1"
end
GetTime = function() return STATE.now end
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
  IsSpellInRange = function(_, u) local r = U(u) return not r or r.range ~= false end,
  GetSpellCooldown = function(id) return { startTime = STATE.cooldowns[id] or 0, duration = 1.5 } end,
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
-- Buffs by name: AURAS[unit .. name], or a spell in a described unit's auras. An aura is a
-- spell ID (no expiry) or { id = ..., expires = GetTime() value, as = spell ID whose name it
-- carries }: in the client every rank answers to the spell's one name.
local function Aura(a)
  if type(a) == "table" then
    return { spellId = a.id, expirationTime = a.expires or 0, name = "A" .. a.id, as = a.as or a.id }
  end
  return { spellId = a, expirationTime = 0, name = "A" .. a, as = a }
end
C_UnitAuras = { GetAuraDataBySpellName = function(u, name)
  if AURAS[u .. name] then return { expirationTime = 0 } end
  local r = U(u)
  for _, a in ipairs(r and r.auras or {}) do
    local aura = Aura(a)
    if "Spell" .. aura.as == name then return aura end
  end
end }
AURAS = {}
-- The installed addons: { name = folder, title, loaded }, by index
ADDONS = {}
C_AddOns = {
  GetAddOnMetadata = function() return "1.0.0" end,
  GetNumAddOns = function() return #ADDONS end,
  GetAddOnInfo = function(i) local a = ADDONS[i] return a.name, a.title, "", true, nil end,
  IsAddOnLoaded = function(i) return ADDONS[i].loaded == true end,
}
C_CurrencyInfo = { GetCoinTextureString = function(m) return m .. "c" end }
UIDropDownMenu_SetWidth = noop
UnitGUID = function(u) if u == "NPC" then return STATE.tradeGuid end return "Player-1-" .. u end
AURALIST = {}
C_UnitAuras.GetAuraDataByIndex = function(u, i)
  local r = U(u)
  local l = AURALIST[u] or (r and r.auras)
  if l and l[i] then return Aura(l[i]) end
end
MACROS = {}
-- Indexes as the client's: account-wide macros 1-120 in their order, character macros from 121
local function MacroIndex(pos)
  local account, character = 0, 0
  for i = 1, pos do if MACROS[i].perChar then character = character + 1 else account = account + 1 end end
  return MACROS[pos].perChar and 120 + character or account
end
local function MacroPos(index) for pos = 1, #MACROS do if MacroIndex(pos) == index then return pos end end end
-- The lowest index of that name, so an account-wide macro comes before a character one
GetMacroIndexByName = function(n)
  local best = 0
  for pos, m in ipairs(MACROS) do
    if m.name == n then local i = MacroIndex(pos) if best == 0 or i < best then best = i end end
  end
  return best
end
GetMacroInfo = function(i) local pos = MacroPos(i) if pos then return MACROS[pos].name, nil, MACROS[pos].body end end
GetNumMacros = function() local a,c=0,0 for _,m in ipairs(MACROS) do if m.perChar then c=c+1 else a=a+1 end end return a,c end
DeleteMacro = function(i) table.remove(MACROS, MacroPos(i)) end
MAX_ACCOUNT_MACROS = 120
CreateMacro = function(n, icon, body, perChar) MACROS[#MACROS+1] = { name = n, body = body, perChar = perChar } return #MACROS end
EditMacro = function(i, n, icon, body) MACROS[MacroPos(i)].body = body end
GetBuildInfo = function() return "1.15.0", "99999", "Oct 1 2026", 16001 end
date = os.date
-- The clock BugGrabber stamps errors with; moves with STATE.now
time = function() return 1792600000 + math.floor(STATE.now) end
-- As research found BugGrabber on Forever: GetDB and GetSessionId, no callback; entries with a
-- Unix time and their session (ruleset plan 2026-10-17-bug-report-details-RESEARCH)
BugGrabber = {
  GetSessionId = function() return 1 end,
  GetDB = function() return {
    { message = "Interface/AddOns/SimpleConjureBar/Bar.lua:10: attempt to index nil",
      stack = "[Interface/AddOns/SimpleConjureBar/Bar.lua]:10: in function 'x'\n[C]: ?", counter = 3,
      time = time(), session = 1, locals = "self=<table>" },
    { message = "OtherAddon error", stack = "[Interface/AddOns/Other/x.lua]:1", counter = 1, time = time(), session = 1 } } end,
}
