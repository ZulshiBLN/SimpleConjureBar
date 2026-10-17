# Changelog

From 1.37.1 on, this file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
versions follow [Semantic Versioning](https://semver.org/). Earlier entries stay as written.

## [1.37.1] - Unreleased

Checked in game on WoW Forever 1.60.1.70450 (interface 16001).

### Added
- Macros tab: an Ice Block macro - the first press casts it, a press during it ends it early.
- Macros tab: stopcasting macros for Fire Blast, Frost Nova, Blink and Counterspell, chosen in a
  dropdown. Each stops the current cast and casts its spell at once; Counterspell aims at the
  focus first. Macro names follow the client's language, cut to 16 characters.

### Changed
- README: two known limits are gone, both verified in game. Russian, Korean and Chinese texts
  render on an English client, and Molten Armor's WoW Forever spell ID (429307) is correct.

### Fixed
- Settings: the language menu no longer cuts the Chinese language names short. Every dropdown
  now grows to fit its longest entry in the current language.

## 1.37
- New "Report bug" button (General tab, bottom left) and `/scb bug`: opens a window with an
  optional description field and a ready-made, pre-selected report (addon version, client,
  language, settings and this addon's Lua errors from BugGrabber/BugSack) to copy with Ctrl+C
  and paste as a GitHub issue. No character name, realm or other personal data is included.

## 1.36
- Macros tab: new button "Show macro" next to "Create Polymorph macro"; opens the Blizzard macro
  window on the character macros.

## 1.35
- New tab "Macros": the "Create Polymorph macro" button moved here from General, with a short
  explanation and a raid marker selection (default: moon) that the macro uses when it is created
  or updated.

## 1.34
- "SCB Polymorph" is now a character macro. An account-wide copy from 1.33 is replaced.

## 1.33
- Removed the option "Show login message": the login message is always shown.
- General tab: the language selection is now the first row, above "Hide in combat".
- New button "Create Polymorph macro" (General tab, bottom left): creates or updates the
  account-wide macro "SCB Polymorph" (focus + moon marker, then Polymorph on the focus).

## 1.32
- Official game names checked against the localized game data (Wowhead tooltip data, Classic):
  - esES/esMX: Runa de Teletransporte, Runa de Portales, Partículas Arcanas
  - itIT: Pulviscolo Arcano
  - ptBR: Runa de Teleporte, Inteligência Arcana
  - ruRU: Порошок чар
  - koKR: 차원이동의 룬, 불가사의한 가루, armor label 냉기 (Frost Armor = 냉기 갑옷), 마나 보석
  - zhTW: 秘法智慧
  - frFR: Intelligence des arcanes

## 1.31
- Section headers and armor labels use Blizzard font objects instead of a custom font size, so
  Russian, Korean and Chinese headers render on every client (no boxes).

## 1.30
- Localization: with an overridden addon language, reagent names, the Arcane Intellect name in the
  Order tab and in the missing-buff hint, and the auto-buy messages use the addon translation
  instead of the client language.

## 1.29
- Intellect: a stronger Intellect buff that our spell cannot overwrite (higher rank of another
  mage, other Intellect buffs found by spell ID) no longer counts as missing. Weaker buffs such
  as Scroll of Intellect still count as missing.
- Combat: armor and Intellect highlights and the Intellect count are frozen at the state of combat
  start (the client restricts aura data in combat) and are re-checked right after combat.
- `/scb debug` also lists your own buffs with their spell IDs.

## 1.28
Security review release.

- Saved settings are validated at login: wrong types fall back to defaults, numbers are clamped
  (scale, amounts, thresholds, speeds, colors, minimap angle, position, language).
- Auto-buy: the purchase loop always ends (at least 1 item per call), items without a gold price
  are never bought, and a 3 second lock after a purchase prevents double purchases.
- New gold reserve for auto-buy (Supplies tab, default 1 gold).
- Trading identifies the partner by GUID instead of the name (realm-safe).
- A /reload in combat sets scale and position of the bar after combat.
- MIT license; author shown as ZulshiBLN.

## 1.27
Code audit release: the findings of the code audit of 1.26 were fixed. Two items are only partly
solvable outside the game client: some behavior still needs in-game verification, and the mana
gem macro can still report the shared cooldown for a second gem.

### Structure
- Split the single 2800-line file into 12 modules (far below the 200 locals limit per chunk).
- All code comments and documentation are in English; added README and changelog.
- Defaults are defined once (`Data.lua`) and applied in a loop; settings have a schema version.

### Performance
- One group scan delivers the Intellect count and the buff targets (was two scans).
- The 1-second Intellect ticker only runs in a group, out of combat, with the button shown.
- Secure attributes are only written when their value changes.
- Group auras are not evaluated in combat; the group is recounted once after combat.
- Rebuilds triggered in the same frame are merged; a target change only updates water/food.
- Highlight animations only run while the highlight is visible.
- Spell names are cached; static tables are no longer created on every update.

### Fixes
- Trading only fills the trade window of the player that was middle-clicked.
- Auto-buy retries once when the vendor list is not ready yet; the chat message now says "Buying".
- The mana gem macro lists owned gems first, then the known but missing gems.
- Pet auras no longer trigger buff recounts.
- The import message of old ConjureBar settings uses the chosen language.

### Localization
- Runtime language switch now uses a key registry instead of matching texts (deterministic).
- Section headers and armor labels use font families, so all alphabets stay available.
- The Arcane Intellect name in the missing-buff hint comes from the client; the hint no longer
  needs a plural ("Missing Arcane Intellect: 3").
- Fixed French and Italian grammar, German terms (Manaedelstein, Gegenstand), "Reload UI" texts.
- Removed 10 unused texts; renamed tab keys to TAB_TRACKING / TAB_SUPPLIES.

### Standards
- TOC: Category and AddOn compartment entry.
- No global names for sliders; modern APIs are preferred over legacy globals.
- "Open Settings" in the WoW options no longer closes the Blizzard panel (taint risk); the
  addon window opens above it instead.
