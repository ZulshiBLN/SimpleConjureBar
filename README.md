# SimpleConjureBar

A slim mage bar for **WoW Forever** (Classic content on the modern Retail client, Interface 16001).
It bundles everything a mage conjures, buffs and travels with into one movable bar.

## Installation

SimpleConjureBar is published on
[CurseForge](https://www.curseforge.com/wow/addons/simpleconjurebar),
[Wago](https://addons.wago.io/addons/simpleconjurebar) and
[GitHub](https://github.com/ZulshiBLN/SimpleConjureBar/releases) - the same files on all three.

**With WowUp** (2.24 or later, which knows WoW Forever): choose your WoW Forever installation,
then *Get Addons* and search for **SimpleConjureBar**. If the search does not find it yet, use
*Install from URL* with `https://github.com/ZulshiBLN/SimpleConjureBar`. WowUp offers every later
release as an update.

**With the CurseForge or Wago app:** search for SimpleConjureBar in your WoW Forever installation.

**By hand:** download `SimpleConjureBar-<version>-forever.zip` from the
[releases](https://github.com/ZulshiBLN/SimpleConjureBar/releases) and unpack it into
`Interface\AddOns` of your WoW Forever installation, so that the folder
`Interface\AddOns\SimpleConjureBar` holds `SimpleConjureBar.toc`.

The addon loads for mages only.

## Buttons

| Button | Left click | Right click | Middle click |
|---|---|---|---|
| Armor | Cast the last armor | Open the armor flyout (choice is remembered) | – |
| Arcane Intellect | Solo: single buff, group: Arcane Brilliance | The other one | – |
| Mana Gem | Use the best gem | Conjure the highest missing gem | – |
| Water / Food | Consume the best item | Conjure (rank fitting a targeted player) | Trade water & food to the target |
| Teleport / Portal | Last destination | Open the destinations (choice is remembered) | – |
| Handle | Move the bar | Lock / unlock | Open the settings |

- **Arcane Intellect** never buffs your current target: solo it always targets you, in a group the
  addon picks the next mana user without the buff (members in range first). In a raid, Brilliance
  goes to the subgroup with the most missing buffs. The button is locked and greyed out in combat.
  The number on the button shows how many mana users are missing the buff; its tooltip names what
  each click casts and on whom - the member, "your group" for Brilliance, in a raid its group.
- **Highlights** - the modern client's glow - show a missing armor, missing Intellect and a missing
  mana gem.
- **Rune counts** on Teleport/Portal change color at the warning threshold and at 0.
- **Auto-buy** buys runes and Arcane Powder at reagent vendors up to the configured amounts and
  never spends below the configured gold reserve (default 1 gold).
- **Flyouts** (armor, teleports, portals) close by themselves a few seconds after the mouse has
  left them, also in combat. The bar cannot be moved in combat; the handle says so.

## Settings

Open with `/scb`, the minimap button, the AddOn compartment, a middle click on the handle or
*Options > AddOns > SimpleConjureBar*. The settings window cannot be opened in combat; an open
window closes when combat starts and reopens afterwards.

- **General**: language, hide in combat, hide the minimap button, scale, border, background
  color, orientation, growth direction, flyout direction (automatic by screen half, or a fixed
  side), how long an open flyout waits for the mouse (1-5 s), demo mode, Report bug, Reload UI
- **Tracking**: show/hide and colors of Armor, Intellect and Mana Gem, highlight speed
- **Supplies**: rune warning threshold and colors, auto-buy, gold reserve and target amounts
- **Order**: drag and drop the button order
- **Macros**: the Polymorph macro with its raid marker, the Ice Block macro, the stopcasting
  macros, and "Show macro" in the bottom right corner (opens the macro window on the
  character tab; the settings window stays open)

In the Polymorph section, "Create macro" creates (or updates) the character macro **SCB Polymorph**:
the first click sets a hostile, living target as focus and marks it with the chosen raid marker
(default: moon); further clicks cast Polymorph on the focus; a dead focus is cleared automatically.

The other macros are named "SCB " plus the spell's name in your client's language (at most 16
characters) and are created or updated the same way, as character macros:

- **Ice Block**: the first press casts Ice Block, a press during it ends it early.
- **Stopcasting macros**: pick Fire Blast, Frost Nova, Blink or Counterspell and click "Create
  macro". The macro stops your current cast and casts the spell at once; Counterspell aims at
  your focus first - the one the Polymorph macro sets - and at your target without one.

A macro for a spell you have not learned yet shows a question mark until you learn it.

"Report bug" opens a window with a ready-made report (addon version, client, language, settings
and this addon's Lua errors from BugGrabber/BugSack) to copy with Ctrl+C and paste as an issue.

## Chat commands

| Command | Action |
|---|---|
| `/scb` | Open the settings window |
| `/scb help` | List all commands |
| `/scb lock` | Lock or unlock the bar |
| `/scb minimap` | Show or hide the minimap button |
| `/scb demo` | Turn demo mode on or off (simulates every button) |
| `/scb reset` | Reset the bar position |
| `/scb bug` | Open the bug report window |
| `/scb debug` | Technical debug output |

`/cbar` still works as an alias from the old addon name "ConjureBar".

## Key bindings

In a section of their own under *Options > Key Bindings > SimpleConjureBar*:

| Key | Action |
|---|---|
| Cast next buff | One press, one cast: what the first highlighted button of the bar (in the bar's order) would fix - your armor, Arcane Intellect on the next member, a mana gem conjured. Nothing when nothing is highlighted. In combat it never casts Arcane Intellect, as the button does not. |
| Open Settings | Opens or closes the settings window; not in combat. |

## Languages

enUS, deDE, frFR, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW. The language follows the client
and can be overridden in the General tab (saved account-wide, applied without reload).

## Code structure

| File | Content |
|---|---|
| `Locales.lua` | All texts per language, locale switching, the key bindings' names |
| `Data.lua` | Spell/item IDs, layout constants, defaults |
| `Core.lua` | AddOn compartment entry points, API shims, saved variables, helpers, font helpers, language registry |
| `Bar.lua` | Bar frame, handle, secure buttons, glow, flyouts, the "Cast next buff" key, colors |
| `Buttons.lua` | Button setup, layout (`Rebuild`), flyout direction and auto-close, counts, the buff key's action, bar events |
| `Bindings.xml` | The two keys the game's Key Bindings offer |
| `Intellect.lua` | Group scan, buff targets, buff count, armor highlight |
| `Merchant.lua` | Reagent auto-buy |
| `Trade.lua` | Trading water and food |
| `Macros.lua` | Character macro "SCB Polymorph", macro window |
| `Report.lua` | Bug report window (report text, BugGrabber errors) |
| `Settings.lua` | Settings window framework and widgets |
| `SettingsPages.lua` | The five settings tabs |
| `Minimap.lua` | Minimap button, AddOn compartment, options panel, the settings key |
| `Main.lua` | Startup and chat commands |

Modules share code through the addon namespace (`ns`). Each file is its own Lua chunk, which keeps
every file far below Lua's limit of 200 local variables per chunk.

## Privacy and security

- No network or addon-channel communication, no chat messages to other players.
- No dynamic code: secure snippets and macros are built from constants only.
- Saved settings are validated at login (types and ranges), so damaged files cannot break the addon.
- No personal data is stored; the trade partner's GUID is only kept in memory for 10 seconds.
- Bug reports contain no character name, realm or other personal data and are only shared when
  the user copies and pastes them.

## License

MIT, see [LICENSE](LICENSE). Author: ZulshiBLN.

## Known limits

- With several mana gems in the bags, a left click in combat may still show the shared cooldown
  message for the second gem line of the macro.
- Armor and Intellect highlights and the Intellect count are frozen during combat (the client
  restricts aura data in combat); they update right after combat.
- Intellect buffs the addon does not know yet can be identified with `/scb debug` (lists your
  buffs with spell IDs).
