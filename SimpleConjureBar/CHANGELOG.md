# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [1.1.0] - Unreleased

### Added
- Buff & Run: a middle click on Arcane Intellect buffs your target and then targets the next
  friendly player, one click per player. It casts Arcane Intellect only, never Brilliance, in the
  rank the player's level accepts, and passes anyone who is no mana user or already has it. It
  does nothing in combat or during the global cooldown, and passes players flagged for PvP unless
  "Allow PvP buffing" is on. Both switches are on the General tab; Buff & Run is on by default.
  It has its own key binding.
- Arcane Intellect and the armor are renewed before they run out: on the Tracking tab you set how
  many minutes before (Intellect 0-15, default 5; armor 0-5, default 3). From then on the button
  glows, counts the buff as needed, and its click - and "Cast next buff" - casts it again; members
  who have no Intellect at all come first. Buff & Run follows the same rule.
- A new bug report: a short form - what happened, where (a list of the addon's parts), details -
  and everything else taken from the game, so a bug can be fixed without asking you back. It
  holds this session's errors with how long ago they came and whether in combat, the addon's
  last 50 actions, the state of its buttons and your loaded addons. It holds nothing personal:
  no names, realm, guild, chat, date or file paths; the window lists what it holds and says that
  an issue is public. The report is one code, already selected; its link opens a GitHub form
  with one field for it, and "Show content" shows what the code holds.
- "Show anchor" on the General tab keeps the bar's handle - move, lock, settings - visible.
  It is off by default; then the handle shows only while the mouse is over it, as before.
- The flyouts of Armor, Teleport and Portal open in a direction you choose on the General tab -
  automatic by screen half as before, up or down for a horizontal bar, right or left for a
  vertical one - and close by themselves 1 to 5 seconds (3 by default) after the mouse has left
  them, also in combat.
- Two keys under Options > Key Bindings > SimpleConjureBar. "Cast next buff" casts, one press at a
  time, what the first highlighted button of the bar would fix: your armor, Arcane Intellect on
  the next member, a mana gem conjured. In combat it keeps what it held when the fight started -
  your armor, if nothing was highlighted then - and never casts Arcane Intellect, as the button
  does not. "Open Settings" opens or closes the settings window.

### Changed
- `/scb debug` prints the state part of a bug report: every button, flyout entry and key with its
  click, the items the addon counts, your group by class and your buffs with minutes left.
- The bug report no longer prints the date and clock, your faction or your exact level (a range
  instead), and no settings the addon does not know.
- Teleport and Portal are greyed out in combat and a left click on them does nothing then, as
  the game refuses them in combat; their flyout still lets you choose.
- A click in the armor, teleport or portal flyout only chooses, and the flyout closes; the button
  on the bar casts the choice. Before, the click in the flyout cast at once.
- Armor, Arcane Intellect and the mana gem are highlighted with the modern client's glow, as a
  spell ready to use is, instead of the marching ants. Its color and speed are set as before; a
  change of the speed shows at once.
- The Arcane Intellect tooltip names what a left click casts and on whom, as it did for the right
  click: the member for a single buff, "your group" for Arcane Brilliance, in a raid its group by
  number.
- A left click on the handle in combat says that the bar cannot move then.

### Fixed
- A click on Arcane Intellect cast it on you again and again when nobody needed it. It now casts
  nothing then, and the tooltip says "everyone has it". In a raid, Brilliance no longer goes to
  your own group when no group in need is in range.
- No flyout opened in combat while one of them held no spell yet - the portals before you learn
  them - and BugSack showed "Invalid frame handle".
- With the flyout direction on automatic, a flyout kept opening towards where the bar had been
  before you moved it.
- On a character of another class, hovering or clicking SimpleConjureBar in the AddOn menu next
  to the minimap raised a Lua error. The entry now does nothing there.

## [1.0.1] - 2026-10-18

### Added
- SimpleConjureBar is also published on CurseForge and Wago, so the WowUp app finds it by
  search.

## [1.0.0] - 2026-10-18

First public release. Checked in game on WoW Forever 1.60.1.70450 (interface 16001).

### Added
- One movable bar for everything a mage conjures, buffs and travels with: armor, Arcane
  Intellect, mana gem, water and food, teleports and portals.
- Arcane Intellect never buffs your target by accident: solo it buffs you, in a group the next
  mana user without the buff, in a raid Brilliance goes to the subgroup missing the most.
- Highlights for a missing armor, Intellect and mana gem.
- Water and food conjured at the rank that fits the targeted player, and traded to them with a
  middle click.
- Rune counts that change color at a warning threshold, and auto-buy of runes and Arcane Powder
  that never spends below a gold reserve.
- Macros: Polymorph on a marked focus, Ice Block, and stopcasting macros for Fire Blast, Frost
  Nova, Blink and Counterspell.
- Report bug (`/scb bug`): a ready-made report without personal data, to paste into a GitHub
  issue.
- Eleven languages, switchable in the settings without a reload.

## Pre-release history

Internal builds 1.27 to 1.37.1, never published. Their numbers come before 1.0.0, not after it;
the entries stay as written.

### [1.37.1] - never published

Checked in game on WoW Forever 1.60.1.70450 (interface 16001).

#### Added
- Macros tab: an Ice Block macro - the first press casts it, a press during it ends it early.
- Macros tab: stopcasting macros for Fire Blast, Frost Nova, Blink and Counterspell, chosen in a
  dropdown. Each stops the current cast and casts its spell at once; Counterspell aims at the
  focus first. Macro names follow the client's language, cut to 16 characters.

#### Changed
- Report bug: the window now names where to send the report - the issues page of the GitHub
  repository, with a form that has a place for it.
- Macros tab: the Polymorph part is laid out like the other sections - its name as header, the
  raid marker, then "Create macro". "Show macro" moved to the bottom right corner and leaves the
  settings window open.
- README: two known limits are gone, both verified in game. Russian, Korean and Chinese texts
  render on an English client, and Molten Armor's WoW Forever spell ID (429307) is correct.
- README: an installation section - with WowUp from the GitHub URL, or by hand from the
  release zip.

#### Fixed
- Macros tab: "Show macro" opens the macro window on the character tab, where the SCB macros
  are, instead of the general one.
- Settings: the language menu no longer cuts the Chinese language names short. Every dropdown
  now grows to fit its longest entry in the current language.

### 1.37
- New "Report bug" button (General tab, bottom left) and `/scb bug`: opens a window with an
  optional description field and a ready-made, pre-selected report (addon version, client,
  language, settings and this addon's Lua errors from BugGrabber/BugSack) to copy with Ctrl+C
  and paste as a GitHub issue. No character name, realm or other personal data is included.

### 1.36
- Macros tab: new button "Show macro" next to "Create Polymorph macro"; opens the Blizzard macro
  window on the character macros.

### 1.35
- New tab "Macros": the "Create Polymorph macro" button moved here from General, with a short
  explanation and a raid marker selection (default: moon) that the macro uses when it is created
  or updated.

### 1.34
- "SCB Polymorph" is now a character macro. An account-wide copy from 1.33 is replaced.

### 1.33
- Removed the option "Show login message": the login message is always shown.
- General tab: the language selection is now the first row, above "Hide in combat".
- New button "Create Polymorph macro" (General tab, bottom left): creates or updates the
  account-wide macro "SCB Polymorph" (focus + moon marker, then Polymorph on the focus).

### 1.32
- Official game names checked against the localized game data (Wowhead tooltip data, Classic):
  - esES/esMX: Runa de Teletransporte, Runa de Portales, Partículas Arcanas
  - itIT: Pulviscolo Arcano
  - ptBR: Runa de Teleporte, Inteligência Arcana
  - ruRU: Порошок чар
  - koKR: 차원이동의 룬, 불가사의한 가루, armor label 냉기 (Frost Armor = 냉기 갑옷), 마나 보석
  - zhTW: 秘法智慧
  - frFR: Intelligence des arcanes

### 1.31
- Section headers and armor labels use Blizzard font objects instead of a custom font size, so
  Russian, Korean and Chinese headers render on every client (no boxes).

### 1.30
- Localization: with an overridden addon language, reagent names, the Arcane Intellect name in the
  Order tab and in the missing-buff hint, and the auto-buy messages use the addon translation
  instead of the client language.

### 1.29
- Intellect: a stronger Intellect buff that our spell cannot overwrite (higher rank of another
  mage, other Intellect buffs found by spell ID) no longer counts as missing. Weaker buffs such
  as Scroll of Intellect still count as missing.
- Combat: armor and Intellect highlights and the Intellect count are frozen at the state of combat
  start (the client restricts aura data in combat) and are re-checked right after combat.
- `/scb debug` also lists your own buffs with their spell IDs.

### 1.28
Security review release.

- Saved settings are validated at login: wrong types fall back to defaults, numbers are clamped
  (scale, amounts, thresholds, speeds, colors, minimap angle, position, language).
- Auto-buy: the purchase loop always ends (at least 1 item per call), items without a gold price
  are never bought, and a 3 second lock after a purchase prevents double purchases.
- New gold reserve for auto-buy (Supplies tab, default 1 gold).
- Trading identifies the partner by GUID instead of the name (realm-safe).
- A /reload in combat sets scale and position of the bar after combat.
- MIT license; author shown as ZulshiBLN.

### 1.27
Code audit release: the findings of the code audit of 1.26 were fixed. Two items are only partly
solvable outside the game client: some behavior still needs in-game verification, and the mana
gem macro can still report the shared cooldown for a second gem.

#### Structure
- Split the single 2800-line file into 12 modules (far below the 200 locals limit per chunk).
- All code comments and documentation are in English; added README and changelog.
- Defaults are defined once (`Data.lua`) and applied in a loop; settings have a schema version.

#### Performance
- One group scan delivers the Intellect count and the buff targets (was two scans).
- The 1-second Intellect ticker only runs in a group, out of combat, with the button shown.
- Secure attributes are only written when their value changes.
- Group auras are not evaluated in combat; the group is recounted once after combat.
- Rebuilds triggered in the same frame are merged; a target change only updates water/food.
- Highlight animations only run while the highlight is visible.
- Spell names are cached; static tables are no longer created on every update.

#### Fixes
- Trading only fills the trade window of the player that was middle-clicked.
- Auto-buy retries once when the vendor list is not ready yet; the chat message now says "Buying".
- The mana gem macro lists owned gems first, then the known but missing gems.
- Pet auras no longer trigger buff recounts.
- The import message of old ConjureBar settings uses the chosen language.

#### Localization
- Runtime language switch now uses a key registry instead of matching texts (deterministic).
- Section headers and armor labels use font families, so all alphabets stay available.
- The Arcane Intellect name in the missing-buff hint comes from the client; the hint no longer
  needs a plural ("Missing Arcane Intellect: 3").
- Fixed French and Italian grammar, German terms (Manaedelstein, Gegenstand), "Reload UI" texts.
- Removed 10 unused texts; renamed tab keys to TAB_TRACKING / TAB_SUPPLIES.

#### Standards
- TOC: Category and AddOn compartment entry.
- No global names for sliders; modern APIs are preferred over legacy globals.
- "Open Settings" in the WoW options no longer closes the Blizzard panel (taint risk); the
  addon window opens above it instead.
