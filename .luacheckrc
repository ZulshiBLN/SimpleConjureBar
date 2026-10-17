-- The globals rule from the ruleset's code.md, made checkable: the addon may
-- write only what the client or the TOC must find by name.
std = "lua51"
max_line_length = false

-- CI installs Lua and LuaRocks into the checkout (.lua/, .luarocks/); their
-- code is not ours to check
exclude_files = { ".lua/**", ".luarocks/**" }

-- WoW's Lua has no file, process or module loading. lua51 would allow them.
not_globals = { "io", "os", "require", "dofile", "loadfile", "module" }

globals = {
    "SimpleConjureBarDB",
    "SimpleConjureBarGlobalDB",
    "ConjureBarDB", -- read once to import the settings of the old name "ConjureBar"
    "SLASH_SIMPLECONJUREBAR1",
    "SLASH_SIMPLECONJUREBAR2",
    "SimpleConjureBar_OnCompartmentClick",
    "SimpleConjureBar_OnCompartmentEnter",
    "SimpleConjureBar_OnCompartmentLeave",
}

-- The WoW API the addon reads, listed by hand so a typo or a removed API is
-- reported instead of trusted. SlashCmdList is shared by every addon; only our
-- own entry may be written.
--
-- Several names here are Classic-era fallbacks Forever no longer has
-- (GetSpellInfo, GetItemInfo, UnitBuff, UIDropDownMenu_*, InterfaceOptions_*,
-- OpacitySliderFrame). The code of the unpublished build 1.37 predates the
-- ruleset; they are listed so the code passes as it stands, and go when the
-- code that reads them goes
-- (ruleset archive/decisions.md).
read_globals = {
    "BackdropTemplateMixin", "BugGrabber", "BuyMerchantItem",
    "C_AddOns", "C_Container", "C_CurrencyInfo", "C_Item", "C_MerchantFrame",
    "C_Spell", "C_SpellBook", "C_Timer", "C_UnitAuras",
    "ChatFontNormal", "CheckInteractDistance", "ClearCursor", "ClickTradeButton",
    "CreateColor", "CreateFrame", "CreateMacro", "DeleteMacro", "EditMacro",
    "GameFontHighlightSmall", "GameFontNormalHuge", "GameTooltip", "GameTooltip_Hide",
    "GetAddOnMetadata", "GetBuildInfo", "GetCVar", "GetCoinText", "GetCoinTextureString",
    "GetContainerItemID", "GetContainerItemInfo", "GetContainerNumSlots",
    "GetCursorPosition", "GetItemCooldown", "GetItemCount", "GetItemIcon", "GetItemInfo",
    "GetLocale", "GetMacroIndexByName", "GetMerchantItemID", "GetMerchantItemInfo",
    "GetMerchantItemLink", "GetMerchantItemMaxStack", "GetMerchantNumItems", "GetMoney",
    "GetNumGroupMembers", "GetNumMacros", "GetNumSubgroupMembers", "GetRaidRosterInfo",
    "GetSpellInfo", "GetSpellTexture", "GetTime", "GetTradePlayerItemLink",
    "InCombatLockdown", "InitiateTrade", "InterfaceOptions_AddCategory",
    "IsInGroup", "IsInRaid", "IsMouseButtonDown", "IsPlayerSpell", "IsSpellInRange",
    "IsSpellKnown", "LoadAddOn", "MAX_ACCOUNT_MACROS", "MAX_CHARACTER_MACROS",
    "MacroFrame", "MacroFrameTab2", "Minimap", "NUM_BAG_SLOTS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NumberFontNormal", "OpacitySliderFrame",
    "PickupContainerItem", "PixelUtil", "RegisterStateDriver", "ReloadUI",
    "STANDARD_TEXT_FONT", "Settings", "ShowMacroFrame", "ShowUIPanel",
    "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize",
    "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth", "UIParent", "UISpecialFrames",
    "UnitBuff", "UnitClass", "UnitExists", "UnitFactionGroup", "UnitGUID", "UnitInRange",
    "UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsFriend", "UnitIsPlayer", "UnitIsUnit",
    "UnitIsVisible", "UnitLevel", "UnitName", "UnregisterStateDriver",
    "date", "strtrim", "tinsert", "wipe",
    SlashCmdList = { fields = { SIMPLECONJUREBAR = { read_only = false } } },
    -- The pre-10.2.5 color picker is configured through these fields; the
    -- current one through SetupColorPickerAndShow. Same baseline as above.
    ColorPickerFrame = { fields = {
        "Content", "GetColorAlpha", "GetColorRGB", "Hide", "HookScript",
        "SetColorRGB", "SetupColorPickerAndShow", "Show",
        hasOpacity = { read_only = false },
        opacity = { read_only = false },
        previousValues = { read_only = false },
        func = { read_only = false },
        opacityFunc = { read_only = false },
        cancelFunc = { read_only = false },
    } },
}

-- Unused locals in the unpublished build 1.37, named one by one so a new one is still reported.
-- Each goes with the first change to its file (ruleset archive/decisions.md).
files["SimpleConjureBar/Bar.lua"] = { ignore = { "211/GAP" } }
files["SimpleConjureBar/Report.lua"] = { ignore = { "211/L" } }

-- Specs run in plain Lua 5.1 under busted, where file access is how they read
-- the addon's sources.
files["tests/"] = {
    std = "lua51+busted",
    read_globals = {
        "io", "require", "loadfile",
        -- What tests/helpers/mock.lua provides to drive the mocked client,
        -- and the named frames the addon creates there
        "NEWOBJ", "FIRE", "RUNTIMERS", "RUNSCRIPT", "TICK", "STATE",
        "SimpleConjureBarSettings",
    },
}

-- The mock *is* the WoW API: defining client globals is its whole job, and
-- the scenario drives it through them.
files["tests/helpers/mock.lua"] = {
    std = "lua51",
    allow_defined_top = true,
    read_globals = { "os" },
    ignore = { "111", "112", "121", "122", "131", "212" },
}
files["tests/scenario_spec.lua"] = {
    std = "lua51+busted",
    allow_defined_top = true,
    ignore = { "111", "112", "113", "121", "122", "143" },
}
