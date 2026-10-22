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
| Arcane Intellect | Solo: single buff, group: Arcane Brilliance | The other one | Buff & Run |
| Mana Gem | Use the best gem | Conjure the highest missing gem | – |
| Water / Food | Consume the best item | Conjure (rank fitting a targeted player) | Trade water & food to the target |
| Teleport / Portal | Last destination | Open the destinations (choice is remembered) | – |
| Handle | Move the bar | Lock / unlock | Open the settings |

- **Arcane Intellect** never buffs your current target: solo it always targets you, in a group the
  addon picks the next mana user without the buff (members in range first). In a raid, Brilliance
  goes to the subgroup with the most missing buffs. The button is locked and greyed out in combat.
  The number on the button shows how many mana users need the buff; its tooltip names what
  each click casts and on whom - the member, "your group" for Brilliance, in a raid its group.
  A buff with less than its renew time left (Tracking tab, 5 minutes by default) is needed again,
  after everyone who has none. When nobody needs it, a click casts nothing and the tooltip says
  "everyone has it"; in a raid Brilliance waits until a group in need is in range.
- **Buff & Run** - a middle click on Arcane Intellect buffs the player you target and then targets
  the next friendly player, so you can buff passing players by clicking again and again. Only
  Arcane Intellect, never Brilliance, in the highest rank his level accepts, and only for a mana
  user who still needs it; anyone else is passed. The game picks the next player, sometimes one
  out of range: then the click only moves on. A click during the global cooldown does nothing,
  so nobody is skipped; in combat nothing happens. A player flagged for PvP is passed - buffing
  him would flag you - unless "Allow PvP buffing" is on, or you are flagged yourself without the
  5-minute timer: by `/pvp`, in a battleground, an arena or a PvP zone. Flagged only by the timer,
  as after buffing a flagged player, you still pass them. Both are switched on the General tab.
- **Highlights** - the modern client's glow - show a missing or expiring armor, missing or expiring
  Intellect and a missing mana gem. An armor glows from its renew time on (3 minutes by default).
- **Rune counts** on Teleport/Portal change color at the warning threshold and at 0.
- **Auto-buy** buys runes and Arcane Powder at reagent vendors up to the configured amounts and
  never spends below the configured gold reserve (default 1 gold).
- **Flyouts** (armor, teleports, portals): a left click on an entry only chooses it; the button on
  the bar casts the choice. They close by themselves a few seconds after the mouse has
  left them, also in combat. The bar cannot be moved in combat; the handle says so.
- **Teleport and Portal** are greyed out in combat, where the game refuses them; their flyout
  still lets you choose the next destination.

## Settings

Open with `/scb`, the minimap button, the AddOn compartment, a middle click on the handle or
*Options > AddOns > SimpleConjureBar*. The settings window cannot be opened in combat; an open
window closes when combat starts and reopens afterwards.

- **General**: language, hide in combat, hide the minimap button, scale, the background of the
  settings and bug report windows (0 % invisible to 100 % solid; 60 % is the look they always
  had), border, show anchor
  (keeps the handle visible; on by default - off, it shows only under the mouse), background
  color, orientation, growth direction, flyout direction (automatic by screen half, or a fixed
  side), how long an open flyout waits for the mouse (1-5 s), demo mode, Buff & Run (on by default)
  with "Allow PvP buffing" (off by default; while you are flagged without a timer, flagged players
  are buffed anyway), Report bug, Reload UI
- **Tracking**: show/hide and colors of Armor, Intellect and Mana Gem, highlight speed; how many
  minutes before it runs out Arcane Intellect (0-15, default 5) and the armor (0-5, default 3)
  count as needed again - 0 means only once they are gone
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

## Reporting a bug

"Report bug" (General tab) or `/scb bug` opens a short form: what happened, where - a list of
the addon's parts - and optional details. Everything else the report takes from the game, so a
bug can be found and fixed without asking you back. The window shows the report as one code,
already selected:

1. Copy the code with Ctrl+C.
2. Open the link below the code: it opens the bug report form on GitHub (a GitHub account is
   needed).
3. Paste the code into its one field, tick the consent box and send it.

"Show content" shows everything the code holds before you pass it on. The window does not open
in combat; one that is open closes when combat starts and comes back after it. Errors come from
BugGrabber/BugSack when installed. To read a code yourself: `lua tools/decode-report.lua`
(see [tools/README.md](tools/README.md)).

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
| `/scb debug` | Technical debug output: the state part of a bug report |

`/cbar` still works as an alias from the old addon name "ConjureBar".

## Key bindings

In a section of their own under *Options > Key Bindings > SimpleConjureBar*:

| Key | Action |
|---|---|
| Cast next buff | One press, one cast: what the first highlighted button of the bar (in the bar's order) would fix - your armor, Arcane Intellect on the next member, a mana gem conjured. Nothing when nothing is highlighted. In combat it keeps what it held when the fight started - your armor, if nothing was highlighted then - and never casts Arcane Intellect, as the button does not. |
| Buff & Run | The Arcane Intellect button's middle click: buffs the target, then targets the next friendly player. Also with the button hidden. One player per press. |
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
| `Log.lua` | The bug report's action log: the last 50 presses and events, in memory |
| `Bar.lua` | Bar frame, handle, secure buttons, glow, flyouts, the "Cast next buff" key, colors |
| `Buttons.lua` | Button setup, layout (`Rebuild`), flyout direction and auto-close, counts, the buff key's action, bar events |
| `Bindings.xml` | The three keys the game's Key Bindings offer |
| `Intellect.lua` | Group scan, buff targets, buff count, armor highlight, Buff & Run |
| `Merchant.lua` | Reagent auto-buy |
| `Trade.lua` | Trading water and food |
| `Macros.lua` | Character macro "SCB Polymorph", macro window |
| `Privacy.lua` | What a bug report may carry: allowlist, name and path filter, locals, size |
| `ReportCode.lua` | The bug report as one code (`SCB1:`), shared with `tools/decode-report.lua` |
| `Report.lua` | Bug report window, report text, state snapshot, loaded addons |
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

### Bug reports

A bug report leaves the game only when you copy its code and send it. **A GitHub issue is
public**: everyone can read it. Write no names or personal data into the form's fields.

- **What it holds, and why** - to find and fix the bug you report: your description, where it
  happened and your details; the addon's version and its settings (known keys only); your
  client's version, build and language; your class, level range (e.g. 20-29) and whether you are
  solo, in a party or a raid; this addon's Lua errors of the current session with how long ago
  they came and whether in combat; its last 50 actions (clicks with spell and item IDs and unit
  tokens such as `party1`, combat, group size, settings changes); the state of its buttons, the
  items it counts, your group by class and your buffs by spell ID; the names and versions of your
  loaded addons, as conflicts need them.
- **What it never holds** - character, realm, guild or other player names; GUIDs; BattleTags or
  account names; chat, mail or whispers; positions or zones; date or clock time; anything from
  the WTF folder; file paths outside `Interface/AddOns`. Strings the addon does not know are shown
  by their length only; free text and error messages pass a filter for the names the game knows,
  GUIDs, BattleTags and paths. Names are matched as whole words the game knows right now: a name
  you type that the game does not know, or one that is part of a longer word - an addon folder
  you named "ZulshiTools", say - can still remain. Check with "Show content".
- **Where it is kept** - the action log in memory only, gone at logout; nothing is written to
  your saved variables for the report.
- **Deletion** - ask in an issue or to the author; the repository owner deletes an issue on
  request.

## License

MIT, see [LICENSE](LICENSE). Author: ZulshiBLN.

## Known limits

- With several mana gems in the bags, a left click in combat may still show the shared cooldown
  message for the second gem line of the macro.
- Armor and Intellect highlights and the Intellect count are frozen during combat (the client
  restricts aura data in combat); they update right after combat.
- Intellect buffs the addon does not know yet can be identified with `/scb debug` (lists your
  buffs with spell IDs).
