-- SimpleConjureBar - static data
-- Spell and item IDs, layout constants and default settings. Loaded before every other module.
-- All IDs are the Classic Era IDs, which WoW Forever uses as well. Molten Armor (429307) is the
-- only WoW Forever specific ID; verified in game on build 1.60.1.70450.

local _, ns = ...

local D = {}
ns.D = D

---------------------------------------------------------------------------
-- Spells and items (highest rank first)
---------------------------------------------------------------------------
-- Conjure spells and the items they create share the same index (index i = same rank).
D.WATER_SPELLS = { 10140, 10139, 10138, 6127, 5506, 5505, 5504 }
D.FOOD_SPELLS  = { 28612, 10145, 10144, 6129, 990, 597, 587 }
D.WATER_ITEMS  = { 8079, 8078, 8077, 3772, 2136, 2288, 5350 }
D.FOOD_ITEMS   = { 22895, 8076, 8075, 1487, 1114, 1113, 5349 }

-- Required level per conjured item, used while the item info is not cached yet
D.MIN_LEVEL_FALLBACK = {
    [5350] = 1, [2288] = 5, [2136] = 15, [3772] = 25, [8077] = 35, [8078] = 45, [8079] = 55,
    [5349] = 1, [1113] = 5, [1114] = 15, [1487] = 25, [8075] = 35, [8076] = 45, [22895] = 55,
}

D.TRAVEL = {
    Horde = {
        { tele = 3567, portal = 11417 }, -- Orgrimmar
        { tele = 3563, portal = 11418 }, -- Undercity
        { tele = 3566, portal = 11420 }, -- Thunder Bluff
    },
    Alliance = {
        { tele = 3561, portal = 10059 }, -- Stormwind
        { tele = 3562, portal = 11416 }, -- Ironforge
        { tele = 3565, portal = 11419 }, -- Darnassus
    },
}

-- Armor spells; only one can be active. Each family offers its best learned rank.
-- Frost Armor and Ice Armor are separate families that share an icon, so only those two
-- get a short text label on the button (see ARMOR_SHORT_KEYS).
D.ARMOR_FAMILIES = {
    { 7301, 7300, 168 },          -- Frost Armor ranks 3-1
    { 10220, 10219, 7320, 7302 }, -- Ice Armor ranks 4-1
    { 22783, 22782, 6117 },       -- Mage Armor ranks 3-1
    { 429307 },                   -- Molten Armor (WoW Forever ID)
}
D.ARMOR_SHORT_KEYS = { "ARMOR_SHORT_FROST", "ARMOR_SHORT_ICE" }
-- One spell ID per family is enough for the buff check: the aura lookup uses the spell name,
-- which is the same for every rank.
D.ARMOR_BUFF_IDS = { 168, 7302, 6117, 429307 }

-- Classes that use mana (Classic rules, hunters included)
D.MANA_CLASSES = {
    MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true,
    SHAMAN = true, PALADIN = true, HUNTER = true,
}

D.SPELL_ARCANE_INTELLECT  = 1459  -- rank 1, also used for the spell name
D.SPELL_ARCANE_BRILLIANCE = 23028
-- Arcane Intellect ranks with the level they are learned at.
-- A target accepts a buff up to 10 levels above its own level.
D.INTELLECT_RANKS = {
    { id = 10157, level = 56 }, { id = 10156, level = 42 }, { id = 1461, level = 28 },
    { id = 1460,  level = 14 }, { id = 1459,  level = 1 },
}

-- Intellect bonus per buff spell. Intellect buffs of the same kind do not stack: a buff that is
-- at least as strong as the rank we would cast cannot be overwritten, so it counts as "buffed".
D.INTELLECT_BUFFS = {
    [1459] = 2, [1460] = 7, [1461] = 15, [10156] = 22, [10157] = 31, -- Arcane Intellect ranks 1-5
    [23028] = 31,                                                  -- Arcane Brilliance
    [8096] = 4, [8097] = 8, [8098] = 12, [12176] = 16,             -- Scroll of Intellect I-IV
}

-- Mana gems. Each kind can be carried once; all of them share one cooldown.
D.MANA_GEMS = {
    { spell = 10054, item = 8008 }, -- Mana Ruby
    { spell = 10053, item = 8007 }, -- Mana Citrine
    { spell = 3552,  item = 5513 }, -- Mana Jade
    { spell = 759,   item = 5514 }, -- Mana Agate
}

-- Macros tab. Ice Block is a Frost talent. The stopcasting spells are listed by the level
-- they are learned at; the first is the default choice. IDs checked on Wowhead (Classic).
D.SPELL_POLYMORPH    = 118 -- rank 1; the name is the same for every rank
D.SPELL_ICE_BLOCK    = 11958
D.SPELL_COUNTERSPELL = 2139 -- aims at the focus first in its macro
D.STOPCAST_SPELLS    = { 2136, 122, 1953, D.SPELL_COUNTERSPELL } -- Fire Blast, Frost Nova, Blink
-- The addon's own translation of each name, shown when the addon language differs from
-- the client's (ns.LocalName)
D.SPELL_NAME_KEYS = {
    [2136] = "SPELL_FIRE_BLAST", [122] = "SPELL_FROST_NOVA", [1953] = "SPELL_BLINK",
    [D.SPELL_COUNTERSPELL] = "SPELL_COUNTERSPELL", [D.SPELL_ICE_BLOCK] = "SPELL_ICE_BLOCK",
    [D.SPELL_POLYMORPH] = "SPELL_POLYMORPH",
}

D.ITEM_ARCANE_POWDER = 17020
D.ITEM_RUNE_TELE     = 17031
D.ITEM_RUNE_PORTAL   = 17032

-- Reagents for auto-buy. Only items that reagent vendors sell (Light Feather is a mob drop).
-- A reagent is only bought while a spell that uses it is known.
D.REAGENTS = {
    { id = D.ITEM_RUNE_TELE,     nameKey = "REAGENT_TELE",   default = 10, need = "tele" },
    { id = D.ITEM_RUNE_PORTAL,   nameKey = "REAGENT_PORTAL", default = 10, need = "portal" },
    { id = D.ITEM_ARCANE_POWDER, nameKey = "REAGENT_POWDER", default = 20, spell = D.SPELL_ARCANE_BRILLIANCE },
}

-- Default button order (can be changed in the Order tab)
D.DEFAULT_ORDER = { "Armor", "Intellect", "ManaGem", "Water", "Food", "Teleport", "Portal" }

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
D.SIZE, D.GAP, D.PAD = 36, 4, 7 -- button size, gap between buttons, bar padding
D.SCALE_MIN, D.SCALE_MAX = 0.3, 2.0
D.AMOUNT_MAX       = 100  -- highest auto-buy target amount per reagent
D.RUNE_WARN_MAX    = 20
D.GOLD_RESERVE_MAX = 1000 -- gold

-- "Marching ants" highlight: Blizzard flip book with 22 frames of 48 px in a 256 px texture
D.ANTS_TEX    = "Interface\\SpellActivationOverlay\\IconAlertAnts"
D.ANTS_FRAMES = 22
D.ANTS_COLS   = 5
D.ANTS_CELL   = 48 / 256
-- Seconds per frame, speed 1 (slow) to 5 (fast); 3 is the default
D.ANTS_STEPS  = { 0.04, 0.02, 0.01, 0.0075, 0.005 }

-- Where bug reports go (shown in the report window). Empty = no link, the window asks the user
-- to send the report to the addon author instead.
D.BUG_REPORT_URL = "https://github.com/ZulshiBLN/SimpleConjureBar/issues"

D.ADDON_ICON = "Interface\\Icons\\INV_Drink_06" -- same icon as in the AddOn list (TOC IconTexture)

---------------------------------------------------------------------------
-- Settings defaults
---------------------------------------------------------------------------
D.DB_VERSION = 3

-- Colors that can be reset with the "Default" button of the color picker
D.COLOR_DEFAULTS = {
    bg              = { r = 0, g = 0,    b = 0,    a = 0.6 }, -- bar background
    countColor      = { r = 1, g = 1,    b = 1,    a = 1 },   -- number on the Intellect button
    antsColor       = { r = 1, g = 0.82, b = 0.2,  a = 1 },   -- Intellect highlight
    armorAntsColor  = { r = 1, g = 0.82, b = 0.2,  a = 1 },   -- Armor highlight
    gemAntsColor    = { r = 1, g = 0.82, b = 0.2,  a = 1 },   -- Mana Gem highlight
    armorLabelColor = { r = 1, g = 1,    b = 1,    a = 1 },   -- armor short labels
    runeWarnColor   = { r = 1, g = 0.6,  b = 0.1,  a = 1 },   -- rune count at/below the warning threshold
    runeZeroColor   = { r = 1, g = 0.15, b = 0.15, a = 1 },   -- rune count at 0
}

-- Plain values (booleans and numbers)
D.VALUE_DEFAULTS = {
    locked        = false,
    hideCombat    = false,
    autoBuy       = true,
    showBorder    = true,
    showIntellect = true,
    showArmor     = true,
    showGem       = true,
    hideMinimap   = false,
    vertical      = false, -- false = horizontal
    growRev       = false, -- false = grow to the right (horizontal) or down (vertical)
    scale         = 1,
    antsSpeed     = 3,
    armorAntsSpeed = 3,
    gemAntsSpeed  = 3,
    runeWarn      = 5,
    goldReserve   = 1,     -- auto-buy never spends below this amount of gold
    minimapAngle  = 225,   -- degrees, 225 = bottom left of the minimap
    macroMarker   = 5,     -- raid marker of the Polymorph macro, 1-8 (5 = moon)
    macroStopcast = D.STOPCAST_SPELLS[1], -- spell of the stopcasting macro button
}
