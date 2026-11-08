# Bulwark

A tanking suite for **WoW: Forever** (interface 16001): combat alerts, a pre-pull audit and one-key raid marking,
in one addon with one window.

> **Work in progress.** This version has the window, the Settings tab and the minimap button. The three feature
> areas move in from the standalone addons in the next steps:
>
> | Tab | Comes from | State |
> |---|---|---|
> | Alerts | TankAlertForever | next |
> | Audit | TankAuditForever | planned |
> | Marking | TankMarkForever | planned |
>
> Until an area has moved in, keep using its standalone addon. Bulwark leaves an area switched off while its
> standalone addon is loaded, so nothing runs twice.

## Opening Bulwark

- `/bwk` (or `/bulwark`) opens and closes the window. Esc closes it too.
- The minimap button: left-click opens or closes the window, right-click opens Settings, drag to move it.

## Commands

| Command | What it does |
|---|---|
| `/bwk` | open or close the window |
| `/bwk alerts`, `/bwk audit`, `/bwk mark` | open that tab |
| `/bwk settings` | open Settings |
| `/bwk status` | show which areas are on |
| `/bwk minimap` | show or hide the minimap button |
| `/bwk reset` | reset the window's size and position |
| `/bwk debug [on\|off]` | debug trace in chat (kept in the saved variables) |
| `/bwk debug cvars on\|off` | the game's Lua error popups and taint log |
| `/bwk errors [clear]` | list or clear errors Bulwark recorded |

## Settings

- **Areas:** turn Alerts, Audit and Marking on or off (also with the switch at the top of each tab).
  Not available in combat.
- **Window:** window size (60-140 %), reset size and position, show or hide the minimap button.
- **Debug:** debug trace, Lua error popups and taint log, recorded errors, last blocked action.

Settings are saved account-wide (`BulwarkDB`); the last tab and page are saved per character (`BulwarkCharDB`).
