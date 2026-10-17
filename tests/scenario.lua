local ns = NS
local function check(cond, msg) if not cond then table.insert(STATE.errors, "CHECK FAILED: " .. msg) end end
SimpleConjureBarDB = nil
ConjureBarDB = { locked = true, runeColor = { r = 1 } }
FIRE("PLAYER_LOGIN")
RUNTIMERS()
local db = SimpleConjureBarDB
check(db.locked == true, "migration kept locked")
check(db.runeColor == nil, "runeColor removed")
check(db.dbVersion == 3, "dbVersion")
local b = ns.buttons
check(b.Water:GetAttribute("type1") == "item", "water type1 item")
check(b.Water:GetAttribute("spell2") == 10140, "water conjure")
check(b.Intellect:GetAttribute("unit1") == "player", "intel solo unit")
check(b.Intellect:GetAttribute("spell1") == 10157, "intel solo single")
check(b.Intellect:GetAttribute("spell2") == 23028, "intel solo right = brilliance")
check(b.ManaGem:GetAttribute("macrotext1") == "/use item:8008\n/use item:8007\n/use item:5513\n/use item:5514", "gem macro owned then missing: " .. tostring(b.ManaGem:GetAttribute("macrotext1")))
check(b.Teleport.count:GetText() == 3, "rune count")
check(b.Intellect.count:GetText() == 1, "intel count solo " .. tostring(b.Intellect.count:GetText()))
-- attribute writes should not repeat
local w = b.Intellect.attrWrites
ns.UpdateBuffState()
check(b.Intellect.attrWrites == w, "no attr writes when unchanged")
-- group
STATE.group = true; STATE.members = 3
FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
check(b.Intellect:GetAttribute("spell1") == 23028, "group left = brilliance")
check(b.Intellect:GetAttribute("unit2") == "player", "group single first missing = player")
AURAS["playerSpell1459"] = true
FIRE("UNIT_AURA", "player"); RUNTIMERS()
check(b.Intellect:GetAttribute("unit2") == "party1", "next target party1: " .. tostring(b.Intellect:GetAttribute("unit2")))
check(b.Intellect.count:GetText() == 2, "count 2")
check(#TICKERS == 1 and not TICKERS[1].cancelled, "ticker running in group")
TICK()
-- combat
STATE.combat = true
FIRE("PLAYER_REGEN_DISABLED")
check(TICKERS[1].cancelled, "ticker stopped in combat")
AURAS["party1Spell1459"] = true
FIRE("UNIT_AURA", "party1"); RUNTIMERS()
check(b.Intellect.count:GetText() == 2, "no recount in combat")
FIRE("UNIT_AURA", "partypet1"); RUNTIMERS()
FIRE("PLAYER_TARGET_CHANGED"); RUNTIMERS()
STATE.combat = false
FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
check(b.Intellect.count:GetText() == 1, "recount after combat " .. tostring(b.Intellect.count:GetText()))
-- raid
STATE.raid = true; STATE.members = 12
FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
check(b.Intellect:GetAttribute("unit1") ~= nil, "raid unit1 " .. tostring(b.Intellect:GetAttribute("unit1")))
STATE.raid = false; STATE.group = false; STATE.members = 0
FIRE("GROUP_ROSTER_UPDATE"); RUNTIMERS()
check(TICKERS[#TICKERS].cancelled, "ticker stopped solo")
-- target
STATE.target = true
FIRE("PLAYER_TARGET_CHANGED"); RUNTIMERS()
-- settings window
SlashCmdList.SIMPLECONJUREBAR("")
check(SimpleConjureBarSettings:IsShown(), "settings shown")
SlashCmdList.SIMPLECONJUREBAR("help")
SlashCmdList.SIMPLECONJUREBAR("lock")
SlashCmdList.SIMPLECONJUREBAR("minimap")
SlashCmdList.SIMPLECONJUREBAR("demo")
RUNTIMERS()
-- demo clicks
for _, k in ipairs({"Water","Food","ManaGem","Intellect","Armor","Teleport"}) do
  RUNSCRIPT(b[k], "OnClick", "LeftButton", false)
  RUNSCRIPT(b[k], "OnClick", "RightButton", false)
end
SlashCmdList.SIMPLECONJUREBAR("demo")
SlashCmdList.SIMPLECONJUREBAR("debug")
SlashCmdList.SIMPLECONJUREBAR("reset")
SlashCmdList.SIMPLECONJUREBAR("xyz")
-- language switch
local tab = SimpleConjureBarSettings
local function findText(frame, wanted)
  for _, r in ipairs(frame.regions) do if r.text == wanted then return true end end
  for _, c in ipairs(frame.children) do
    if c.fs and c.fs.text == wanted then return true end
    if findText(c, wanted) then return true end
  end
  return false
end
check(findText(tab, "Allgemein") or findText(tab, ns.L.TAB_GENERAL), "general tab text de")
ns.ApplyLanguage("koKR"); RUNTIMERS()
check(findText(tab, ns.L.TAB_GENERAL), "tab text ko")
check(findText(ns.bar, ns.L.DEMO_LABEL), "demo label ko")
ns.ApplyLanguage("enUS"); RUNTIMERS()
check(findText(ns.bar, "DEMO"), "demo label back to DEMO")
check(findText(tab, "Reload UI"), "reload en")
-- merchant
STATE.merchantItems = 3
FIRE("MERCHANT_SHOW")
check(#BUYS == 2, "bought 2 reagents " .. #BUYS)
STATE.merchantItems = 0; BUYS = {}; GetTime = function() return 200 end
FIRE("MERCHANT_SHOW"); STATE.merchantItems = 3; FIRE("MERCHANT_UPDATE"); FIRE("MERCHANT_UPDATE")
check(#BUYS == 2, "deferred buy once " .. #BUYS)
-- trade
STATE.target = true
RUNSCRIPT(b.Water, "OnClick", "MiddleButton", false)
STATE.tradeGuid = "Player-1-other"; FIRE("TRADE_SHOW")
RUNSCRIPT(b.Water, "OnClick", "MiddleButton", false)
STATE.tradeGuid = "Player-1-target"; FIRE("TRADE_SHOW")
-- combat menu block
SimpleConjureBarSettings:Hide()
STATE.combat = true; FIRE("PLAYER_REGEN_DISABLED")
SlashCmdList.SIMPLECONJUREBAR("")
check(not SimpleConjureBarSettings:IsShown(), "menu blocked in combat")
STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED")
-- compartment
SimpleConjureBar_OnCompartmentClick("SimpleConjureBar", "LeftButton")
SimpleConjureBar_OnCompartmentEnter("SimpleConjureBar", UIParent)
for _, line in ipairs(CHAT) do io.write("CHAT: ", line, "\n") end
-- N1: autobuy off while waiting, then on again: only one purchase round
BUYS = {}; GetTime = function() return 300 end
STATE.merchantItems = 0; FIRE("MERCHANT_SHOW")
SimpleConjureBarDB.autoBuy = false; FIRE("MERCHANT_CLOSED")
SimpleConjureBarDB.autoBuy = true; STATE.merchantItems = 3; FIRE("MERCHANT_SHOW"); FIRE("MERCHANT_UPDATE")
check(#BUYS == 2, "N1 no double buy " .. #BUYS)
ARMOR_BEFORE = NS.buttons.Armor.antsShown
-- combat freeze: buffed before combat, auras unreadable in combat -> state stays
STATE.group = false; AURAS = { ["playerSpell1459"] = true }; AURALIST = {}
NS.UpdateBuffState()
check(NS.buttons.Intellect.count:GetText() == "", "buffed before combat")
STATE.combat = true; FIRE("PLAYER_REGEN_DISABLED"); AURAS = {}
FIRE("UNIT_AURA", "player"); RUNTIMERS(); NS.UpdateBuffState()
check(NS.buttons.Intellect.count:GetText() == "", "frozen in combat")
check(not NS.buttons.Armor.antsShown or NS.buttons.Armor.antsShown == ARMOR_BEFORE, "armor frozen")
STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
check(NS.buttons.Intellect.hint2 and NS.buttons.Intellect.hint2:find("1$"), "hint format " .. tostring(NS.buttons.Intellect.hint2))
SettingsPanel = CreateFrame("Frame", "SettingsPanel")
NS.OpenSettings(true)
check(SimpleConjureBarSettings:IsShown() and SettingsPanel:IsShown(), "open above blizzard")
SimpleConjureBarSettings:Hide()
-- gold reserve: 1000 gold reserve with 100 gold -> nothing bought
SimpleConjureBarDB.goldReserve = 1000; BUYS = {}; GetTime = function() return 500 end
ITEMS[17031] = 0; ITEMS[17020] = 0
STATE.merchantItems = 3; FIRE("MERCHANT_SHOW")
check(#BUYS == 0, "reserve blocks buying " .. #BUYS)
SimpleConjureBarDB.goldReserve = 1
FIRE("MERCHANT_SHOW"); local n1 = #BUYS
FIRE("MERCHANT_CLOSED"); FIRE("MERCHANT_SHOW")
check(#BUYS == n1 and n1 > 0, "buy lock prevents double buy " .. n1 .. "/" .. #BUYS)

-- stronger/other intellect buffs by spell ID
STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
AURAS = {}; AURALIST = { player = { 12176 } }   -- scroll IV (16) < our rank 31 -> missing
NS.UpdateBuffState()
check(NS.buttons.Intellect.count:GetText() == 1, "weaker scroll still missing")
AURALIST = { player = { 999, 10157 } }           -- AI rank 5 with a different name -> covered
NS.UpdateBuffState()
check(NS.buttons.Intellect.count:GetText() == "", "stronger buff by id counts")
SlashCmdList.SIMPLECONJUREBAR("debug")
MACROS = { { name = "SCB Polymorph", body = "old" } }
NS.CreatePolymorphMacro(); NS.CreatePolymorphMacro()
check(#MACROS == 1 and MACROS[1].name == "SCB Polymorph" and MACROS[1].perChar == true, "macro created once, character")
check(MACROS[1].body:find("Spell118"), "macro body")
check(#MACROS[1].body <= 255, "macro length " .. #MACROS[1].body)
SimpleConjureBarDB.macroMarker = 8
NS.CreatePolymorphMacro()
check(MACROS[1].body:find("/tm %[@focus,harm,nodead%] 8"), "macro uses chosen marker")
ShowMacroFrame = function() SHOWN_MACRO = true end
SimpleConjureBarSettings:Show(); NS.ShowMacroWindow(); check(SHOWN_MACRO and not SimpleConjureBarSettings:IsShown(), "show macro")
SlashCmdList.SIMPLECONJUREBAR("bug")
local r = SimpleConjureBarReport
check(r and r:IsShown(), "report window shown")
local txt = r.report:GetText() or ""
check(txt:find("Addon version: 1.27") and txt:find("Bar.lua:10") and not txt:find("OtherAddon") and txt:find("x3"), "report content")
check(not txt:find("Name_player"), "no character name")
r.desc:SetText("Bar vanished"); RUNSCRIPT(r.desc, "OnTextChanged", true)
check((r.report:GetText() or ""):find("Bar vanished"), "description in report")
io.write(r.report:GetText(), "\n")
