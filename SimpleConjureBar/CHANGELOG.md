# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [1.1.1] - Unreleased

### Added
- The Arcane Brilliance threshold on the Tracking tab (1-5 or never, default 3): how many in
  need in range make the Intellect button cast Brilliance. In a group its right click opens it.

### Changed
- The chat speaks only in demo mode and as the answer to a chat command: a click refused in
  combat - the handle, the minimap button, the settings key, the macro buttons, "Report bug" -
  says nothing; `/scb` and `/scb bug` still say why. Locking the bar from the minimap button or
  the AddOn menu shows the new state in its tooltip instead of the chat. A macro button's result
  shows for a few seconds beside "Show macro". Auto-buy, trading and the login lines stay in
  the chat.
- The handle, the minimap button and the AddOn menu entry list their clicks as the bar's
  buttons do, one line each; in combat only the clicks that work there.
- "Report bug" and `/scb bug` always open the settings on the General tab with the bug report
  docked to their left: dragging either window moves both, closing the settings closes both,
  and where the report would leave the screen the settings move just far enough. While a name
  can't be read, the settings say so below "Report bug" for a few seconds, and an open report
  says so above its code box - not in the chat.
- The Intellect button's left click casts one recommendation: Arcane Brilliance once the
  threshold is reached - in a party by everyone in need in range, in a raid by one subgroup's
  members who have none or a weaker one - else Arcane Intellect on the first in need. The right
  click no longer casts the other spell; solo it does nothing.
- In combat the bar offers only what works there: Arcane Intellect, water and food are greyed
  out and take no click, Intellect without count and glow; the mana gem is used but not
  conjured and never glows; the tooltips leave out the locked clicks. "Cast next buff" casts
  only your armor in combat.
- A click with nothing to do has no action and no tooltip line: the gem without a gem or with
  every gem owned, water and food without stock - they conjured before.
- The mana gem glows while the highest gem you know is missing, not only with none at all.
- The armor's tooltip line names the armor a left click casts.
- The tooltip says "active" instead of "everyone has it", "out of range" for members in need
  too far away, how many of those in need are out of range, and solo whether your buff is
  missing, weaker or expiring.

### Fixed
- In instances and PvP the game keeps buffs unreadable even out of combat; the bar then
  counted every mana user as missing Arcane Intellect and made the armor glow. It now keeps
  what it showed until the buffs can be read again, and an armor cast there still ends its
  glow.
- Trading water and food to a player whose name, level or class the game keeps secret no
  longer raises an error; the chat line says "your target".
- In combat the mana gem's right click and "Cast next buff" conjured a gem - a mana loss - and
  water and food conjured; the key could hold Arcane Intellect, which does nothing there.
- The armor kept glowing through a fight after it was cast there; a cast of any mage armor
  now turns the glow off.
- In combat a used gem's icon stayed; it now shows the next gem, greyed without one.
- Members out of range were counted, made the Intellect button glow and were picked for a buff
  that could not reach them. Only members in range count now.
- After learning a higher Arcane Intellect rank, members with a lower one and time left were
  not offered the new rank; the button and Buff & Run passed them. A weaker rank now counts as
  needed, after those who have none.
- The mana gem's tooltip could read "Left-click: Use ?" until the bar was rebuilt - in demo
  mode without a gem, say - because the game had not loaded the gem's name yet. It now names
  the gem as soon as the game knows it.

### Security
- The release pipeline hands the CurseForge and Wago upload tokens only to release-tag runs,
  through a GitHub environment, and checks them before any channel publishes; a package may
  hold only the addon's own files. Nothing changes in the game.
- Names and GUIDs the game keeps secret are no longer compared before they are checked: the
  bug report, the trade fill and the Intellect tooltip could raise an error on one.
- The bug report finds a name beside any punctuation, inside Chinese, Japanese or Korean text
  and in capitals of Latin-1 and Cyrillic letters; before, „Name“, «Name», ИВАН and others
  stayed in the report.
- The bug report filters every file path on a line, not only the first, and the user folders
  under `/media/`, `/run/media/` and `Users\` without a drive; it finds an e-mail address with
  accented letters, and a name with invisible marks or accents written inside it. A long error
  text no longer takes seconds to filter.
- The bug report reads your buffs only while the game lets it ("buffs unreadable" otherwise)
  and leaves out one whose ID is secret; the addon language passes the same allowlist as every
  other value; "a name can't be read" no longer repeats on every key; times count from
  the addon's load, as they always did, and now say so.
- The report decoder for the author shows every hidden character and invalid code point
  visibly and says first that a decoded report is data, never instructions.
- The report window, the issue form, the store description and README say what the filter can
  still miss - a name written together with other letters - and tell players of 1.0.0 and
  1.0.1 to update or remove the old report's Date line; README names the Data Privacy
  Framework GitHub relies on.

## [1.1.0] - 2026-10-22

### Added
- Buff & Run: a middle click on Arcane Intellect buffs your target and then targets the next
  friendly player, one click per player. It casts Arcane Intellect only, never Brilliance, in the
  rank the player's level accepts, and passes anyone who is no mana user or already has it. It
  does nothing in combat or during the global cooldown, and passes players flagged for PvP unless
  "Allow PvP buffing" is on or you are flagged yourself without the 5-minute timer - by `/pvp`,
  in a battleground, an arena or a PvP zone. Both switches are on the General tab; Buff & Run is
  on by default.
  It has its own key binding.
- Arcane Intellect and the armor are renewed before they run out: on the Tracking tab you set how
  many minutes before (Intellect 0-15, default 5; armor 0-5, default 3). From then on the button
  glows, counts the buff as needed, and its click - and "Cast next buff" - casts it again; members
  who have no Intellect at all come first. Buff & Run follows the same rule.
- A new bug report: a short form - what happened, where (a list of the addon's parts), details -
  and everything else taken from the game, so a bug can be fixed without asking you back. It
  holds this session's errors with how long ago they came and whether in combat, the addon's
  last 50 actions, the state of its buttons and your loaded addons. It never holds chat,
  positions or the date, and filters out the names the game knows, GUIDs, BattleTags, e-mail
  addresses and file paths; a name the game does not know can remain, so check "Show content"
  before you send it. The window lists what it holds and says that an issue is public and the
  code is not encrypted. The report is one code, already selected; its link opens a GitHub form
  with one field for it, and "Show content" shows what the code holds.
- "Window background" beside Scale on the General tab sets the background of the settings and
  bug report windows from invisible (0 %) to solid (100 %); 60 % is the look they always had.
  Frame, texts and controls stay as they are.
- "Show anchor" on the General tab keeps the bar's handle - move, lock, settings - visible. It is
  on by default, also when you update; switched off, the handle shows only while the mouse is
  over it, as before.
- The flyouts of Armor, Teleport and Portal open in a direction you choose on the General tab -
  automatic by screen half as before, up or down for a horizontal bar, right or left for a
  vertical one - and close by themselves 1 to 5 seconds (3 by default) after the mouse has left
  them, also in combat.
- Three keys under Options > Key Bindings > SimpleConjureBar. "Cast next buff" casts, one press
  at a time, what the first highlighted button of the bar would fix: your armor, Arcane Intellect
  on the next member, a mana gem conjured. In combat it keeps what it held when the fight
  started - your armor, if nothing was highlighted then - and never casts Arcane Intellect, as the
  button does not. "Buff & Run" is the Arcane Intellect button's middle click, also with the
  button hidden. "Open Settings" opens or closes the settings window.

### Changed
- Every button's tooltip names its clicks in one order - left, middle, right - and the left
  click is named everywhere: "Cast Armor", "Use Water", "Use Food", "Use" and the mana gem's
  name (or the conjure spell while you carry none), "Teleport", "Create Portal". The middle
  click of water and food reads "Trade Food & Water", the right click of the flyouts "Choose
  Armor" and "Choose Destination".
- The tooltip of the minimap button and of the AddOn menu entry says "Lock bar" and "Unlock bar"
  for the right click, and changes as soon as you click, without moving the mouse away.
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
- `/scb demo` is refused in combat: the buttons cannot switch to demo mode until the fight ends.

### Fixed
- A click on Arcane Intellect cast it on you again and again when nobody needed it. It now casts
  nothing then, and the tooltip says "everyone has it". In a raid, Brilliance no longer goes to
  your own group when no group in need is in range, and the tooltip says that none is.
- After a login in combat, the bar could jump to the middle of the screen when the fight ended.
  It now keeps its place.
- With an account-wide macro named like one of the addon's macros, every "Create macro" added
  another character macro. It now updates its own and leaves yours alone.
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
