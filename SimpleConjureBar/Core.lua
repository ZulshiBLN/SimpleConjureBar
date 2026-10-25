-- SimpleConjureBar - core
-- API shims, chat output, saved variables, spell/item helpers, attribute helper,
-- font families and the runtime language registry. Every other module builds on this file.

local ADDON_NAME, ns = ...
local D, L = ns.D, ns.L

-- The AddOn compartment: the TOC names these three functions for every class, so they exist
-- before the mage check below. For a mage Minimap.lua sets what they call; for any other
-- class a click does nothing.
function SimpleConjureBar_OnCompartmentClick(...)
    if ns.CompartmentClick then ns.CompartmentClick(...) end
end
function SimpleConjureBar_OnCompartmentEnter(...)
    if ns.CompartmentEnter then ns.CompartmentEnter(...) end
end
function SimpleConjureBar_OnCompartmentLeave(...)
    if ns.CompartmentLeave then ns.CompartmentLeave(...) end
end

-- The addon is mage-only. Every module checks this flag and stops loading otherwise.
local _, playerClass = UnitClass("player")
ns.enabled = (playerClass == "MAGE")
if not ns.enabled then return end

---------------------------------------------------------------------------
-- API compatibility (modern C_* namespaces first, legacy globals as fallback)
---------------------------------------------------------------------------
local API = {}
ns.API = API

local SpellBookKnown = C_SpellBook and C_SpellBook.IsSpellKnown
local LegacyKnown = IsPlayerSpell or IsSpellKnown
-- Both checks are combined: C_SpellBook and IsPlayerSpell differ slightly for spell ranks,
-- and a rank counts as known if either API reports it.
function API.Known(id)
    if SpellBookKnown and SpellBookKnown(id) then return true end
    return LegacyKnown and LegacyKnown(id) or false
end
API.GetSpellTex  = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
API.GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
API.ItemCount    = (C_Item and C_Item.GetItemCount) or GetItemCount
API.ItemIcon     = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
API.ItemName     = (C_Item and C_Item.GetItemNameByID) or function(id) return (GetItemInfo(id)) end
API.ItemInfo     = (C_Item and C_Item.GetItemInfo) or GetItemInfo
API.ItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
API.MoneyText    = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString or GetCoinText
API.BACKDROP_TPL = BackdropTemplateMixin and "BackdropTemplate" or nil

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.ADDON_NAME = ADDON_NAME
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "?"

local ItemCount, Known, GetSpellName = API.ItemCount, API.Known, API.GetSpellName

---------------------------------------------------------------------------
-- Chat output
---------------------------------------------------------------------------
-- A value the client keeps secret - a name, a GUID, a spell ID - errors when it is compared or
-- truth-tested: ask this first (rules/code.md)
function ns.IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

function ns.Print(msg)
    print("|cff69ccf0SimpleConjureBar|r: " .. msg)
end

function ns.DemoPrint(fmt, ...)
    ns.Print("|cffff9933" .. L.DEMO .. "|r: " .. fmt:format(...))
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local db
local dbCallbacks = {}

-- Modules keep their own local reference to the settings table; it exists after PLAYER_LOGIN.
function ns.OnDBReady(fn)
    dbCallbacks[#dbCallbacks + 1] = fn
    if db then fn(db) end
end

function ns.CopyColor(c) return { r = c.r, g = c.g, b = c.b, a = c.a } end

-- Number from saved data, clamped to [lo, hi]; wrong types and NaN fall back to the default.
-- Saved variables are plain files that can be edited or damaged, so every value is checked.
local function Num(v, lo, hi, default, integer)
    v = tonumber(v)
    if not v or v ~= v then v = default end
    v = math.max(lo, math.min(hi, v))
    if integer then v = math.floor(v) end
    return v
end

-- Returns true when the settings of the old addon name "ConjureBar" were imported.
function ns.InitDB()
    local migrated = false
    if type(SimpleConjureBarDB) ~= "table" then SimpleConjureBarDB = nil end
    if type(SimpleConjureBarGlobalDB) ~= "table" then SimpleConjureBarGlobalDB = nil end
    if not SimpleConjureBarDB and type(ConjureBarDB) == "table" then
        SimpleConjureBarDB = ConjureBarDB
        migrated = true
    end
    ConjureBarDB = nil
    SimpleConjureBarDB = SimpleConjureBarDB or {}
    SimpleConjureBarGlobalDB = SimpleConjureBarGlobalDB or {}
    db = SimpleConjureBarDB

    -- Validation: wrong types are replaced by the default, numbers are clamped to their range
    for key, value in pairs(D.VALUE_DEFAULTS) do
        if type(db[key]) ~= type(value) then db[key] = value end
    end
    local V = D.VALUE_DEFAULTS
    db.scale        = Num(db.scale, D.SCALE_MIN, D.SCALE_MAX, V.scale)
    db.runeWarn     = Num(db.runeWarn, 0, D.RUNE_WARN_MAX, V.runeWarn, true)
    db.goldReserve  = Num(db.goldReserve, 0, D.GOLD_RESERVE_MAX, V.goldReserve, true)
    db.minimapAngle = Num(db.minimapAngle, 0, 360, V.minimapAngle)
    db.macroMarker  = Num(db.macroMarker, 1, 8, V.macroMarker, true)
    -- A number is not enough: only the stopcasting spells may be chosen
    local stopcastKnown = false
    for _, id in ipairs(D.STOPCAST_SPELLS) do
        if db.macroStopcast == id then stopcastKnown = true end
    end
    if not stopcastKnown then db.macroStopcast = V.macroStopcast end
    if not D.FLYOUT_DIRS[db.flyoutDir] then db.flyoutDir = V.flyoutDir end
    db.flyoutAutoClose = Num(db.flyoutAutoClose, D.AUTOCLOSE_MIN, D.AUTOCLOSE_MAX, V.flyoutAutoClose, true)
    db.intellectRenewMinutes = Num(db.intellectRenewMinutes, 0, D.INTELLECT_RENEW_MAX, V.intellectRenewMinutes, true)
    db.armorRenewMinutes = Num(db.armorRenewMinutes, 0, D.ARMOR_RENEW_MAX, V.armorRenewMinutes, true)
    db.brillianceThreshold = Num(db.brillianceThreshold, 1, D.BRILLIANCE_NEVER, V.brillianceThreshold, true)
    db.windowOpacity = Num(db.windowOpacity, 0, 100, V.windowOpacity, true)
    for _, key in ipairs({ "antsSpeed", "armorAntsSpeed", "gemAntsSpeed" }) do
        db[key] = Num(db[key], 1, #D.GLOW_DURATIONS, V[key], true)
    end
    for key, color in pairs(D.COLOR_DEFAULTS) do
        local c = db[key]
        if type(c) ~= "table" then
            db[key] = ns.CopyColor(color)
        else
            for _, f in ipairs({ "r", "g", "b", "a" }) do c[f] = Num(c[f], 0, 1, color[f]) end
        end
    end
    if type(db.point) ~= "string" or type(db.rel) ~= "string"
        or type(db.x) ~= "number" or type(db.y) ~= "number" or db.x ~= db.x or db.y ~= db.y then
        db.point, db.rel, db.x, db.y = nil, nil, nil, nil -- invalid position: back to the default
    end
    if type(db.dbVersion) ~= "number" then db.dbVersion = 1 end
    if type(db.order) ~= "table" then db.order = nil end
    if type(db.last) ~= "table" then db.last = nil end
    if type(db.amounts) ~= "table" then db.amounts = nil end
    if SimpleConjureBarGlobalDB.language ~= nil and not ns.locales[SimpleConjureBarGlobalDB.language] then
        SimpleConjureBarGlobalDB.language = nil -- unknown language code
    end

    -- Schema migrations
    if (db.dbVersion or 1) < 2 then
        db.runeColor = nil -- removed setting: the normal rune count is always white
    end
    if db.dbVersion < 3 then
        db.showGreeting = nil -- removed setting: the login message is always shown
    end
    -- Version 4 adds flyoutDir, flyoutAutoClose, buffRun, pvpBuff, showAnchor,
    -- intellectRenewMinutes, armorRenewMinutes, windowOpacity and brillianceThreshold; the
    -- defaults above fill them in
    db.dbVersion = D.DB_VERSION

    -- Button order: keep the saved order, drop unknown keys, append new buttons at the end
    local order, seen, valid = {}, {}, {}
    for _, k in ipairs(D.DEFAULT_ORDER) do valid[k] = true end
    for _, k in ipairs(db.order or D.DEFAULT_ORDER) do
        if valid[k] and not seen[k] then order[#order + 1] = k; seen[k] = true end
    end
    for _, k in ipairs(D.DEFAULT_ORDER) do
        if not seen[k] then order[#order + 1] = k end
    end
    db.order = order

    db.demo    = false -- demo mode always starts switched off
    db.last    = db.last or {}
    db.amounts = db.amounts or {}
    for _, r in ipairs(D.REAGENTS) do
        db.amounts[r.id] = Num(db.amounts[r.id], 0, D.AMOUNT_MAX, r.default, true)
    end

    for _, fn in ipairs(dbCallbacks) do fn(db) end
    return migrated
end

---------------------------------------------------------------------------
-- Spell and item helpers
---------------------------------------------------------------------------
-- Demo mode: every spell counts as known and clicks are only simulated (never saved)
local function IsDemo() return db and db.demo end
local function IsKnown(id) return IsDemo() or Known(id) end
ns.IsDemo, ns.IsKnown = IsDemo, IsKnown

-- Spell names only depend on the client language, so they are cached once resolved
local spellNames = {}
function ns.SpellName(id)
    local name = spellNames[id]
    if not name then
        name = GetSpellName(id)
        spellNames[id] = name
    end
    return name
end

function ns.BestSpell(list)
    for _, id in ipairs(list) do
        if IsKnown(id) then return id end
    end
end

function ns.BestItem(list)
    for _, id in ipairs(list) do
        if (ItemCount(id) or 0) > 0 then return id end
    end
end

function ns.ItemMinLevel(id)
    local minLevel = select(5, API.ItemInfo(id))
    return minLevel or D.MIN_LEVEL_FALLBACK[id] or 1
end

-- Level of a friendly player in the target, otherwise nil
function ns.TargetPlayerLevel()
    local u = "target"
    if UnitExists(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player") and UnitIsFriend("player", u) then
        local level = UnitLevel(u)
        if level and level > 0 then return level end
    end
end

-- Conjure rank: the best rank the targeted player can use, otherwise the highest known rank.
-- Returns the spell and, when chosen for a target, that target's level.
function ns.ConjureSpellFor(spells, items)
    local best = ns.BestSpell(spells)
    local level = ns.TargetPlayerLevel()
    if not best or not level then return best end
    for i, id in ipairs(spells) do
        if IsKnown(id) and ns.ItemMinLevel(items[i]) <= level then return id, level end
    end
    return best
end

function ns.KnownArmor()
    local list = {}
    for _, family in ipairs(D.ARMOR_FAMILIES) do
        for _, id in ipairs(family) do
            if IsKnown(id) then list[#list + 1] = id break end
        end
    end
    return list
end

-- Short label shown on the armor icon (only Frost and Ice Armor need one, they share an icon)
function ns.ArmorShortName(id)
    for i, family in ipairs(D.ARMOR_FAMILIES) do
        for _, fid in ipairs(family) do
            if fid == id then
                local key = D.ARMOR_SHORT_KEYS[i]
                return key and L[key] or ""
            end
        end
    end
    return ""
end

-- Upgrades a remembered armor spell to the best known rank of the same family
-- (e.g. Frost Armor rank 1 -> rank 3 after learning it)
function ns.NormalizeArmor(id)
    for _, family in ipairs(D.ARMOR_FAMILIES) do
        for _, fid in ipairs(family) do
            if fid == id then
                for _, best in ipairs(family) do
                    if IsKnown(best) then return best end
                end
            end
        end
    end
    return id
end

function ns.KnownTravel(key)
    local list = {}
    for _, t in ipairs(D.TRAVEL[UnitFactionGroup("player")] or {}) do
        if IsKnown(t[key]) then list[#list + 1] = t[key] end
    end
    return list
end

-- Secure attributes are only written when they change: every SetAttribute triggers
-- OnAttributeChanged on the secure button, which is wasted work for unchanged values.
function ns.SetAttr(b, key, value)
    if b:GetAttribute(key) ~= value then b:SetAttribute(key, value) end
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
-- Localized text always uses Blizzard font objects (GameFontNormal and friends): they are font
-- families with one file per alphabet, so Cyrillic, Korean and Chinese render on every client.
-- FontString:SetFont(file) replaces such a family with a single (Latin) file and turns other
-- alphabets into boxes, so it is only used for digits and Latin-only text.
function ns.SetLatinFont(fs, base, size, flags)
    fs:SetFont((base and base:GetFont()) or STANDARD_TEXT_FONT, size, flags or "")
end

-- First existing font object of a list (font object names differ between client versions)
function ns.FontObject(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if _G[name] then return name end
    end
end

---------------------------------------------------------------------------
-- Runtime language switch
-- Every localized text is registered with its key (and format arguments), so a language
-- change re-renders exactly these texts. No text is ever matched by its content.
---------------------------------------------------------------------------
local registry = setmetatable({}, { __mode = "k" }) -- object -> key | function | { key, args... }
local languageCallbacks = {}

local function Resolve(entry)
    local kind = type(entry)
    if kind == "function" then return entry() end
    if kind == "table" then return L[entry[1]]:format(unpack(entry, 2)) end
    return L[entry]
end

-- Names that come from the game client (items, spells) are in the client language. When the
-- addon language is overridden, the addon's own translation is used instead, so the window
-- does not mix two languages.
function ns.LocalName(clientName, key)
    if clientName and ns.GetLocaleCode() == ns.clientLocale then return clientName end
    return L[key]
end

-- Sets a localized text on a FontString or Button and keeps it up to date on language changes.
-- key: locale key, or a function returning the text. Extra arguments are format arguments.
function ns.SetL(obj, key, ...)
    local entry = key
    if select("#", ...) > 0 then entry = { key, ... } end
    registry[obj] = entry
    obj:SetText(Resolve(entry))
end

-- fn runs after every language change (layout updates, button labels)
function ns.OnLanguageChanged(fn)
    languageCallbacks[#languageCallbacks + 1] = fn
end

function ns.ApplyLanguage(code)
    if code == ns.GetLocaleCode() then return end
    ns.SetLocale(code)
    for obj, entry in pairs(registry) do obj:SetText(Resolve(entry)) end
    for _, fn in ipairs(languageCallbacks) do fn() end
end
