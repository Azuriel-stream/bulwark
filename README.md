# Bulwark

A tanking suite for **WoW: Forever** (interface 16001): combat alerts, a pre-pull audit and one-key raid marking,
in one addon with one window.

> **Work in progress.** The feature areas move in from the standalone addons one at a time:
>
> | Tab | Comes from | State |
> |---|---|---|
> | Alerts | TankAlertForever | moved in (0.2.0) |
> | Audit | TankAuditForever | moved in (0.3.0) |
> | Marking | TankMarkForever | next |
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
| `/bwk alerts test miss\|cc\|disarm\|whisper [name]` | send a test alert through the real channel |
| `/bwk alerts status` | show the Alerts settings |
| `/bwk audit lock\|unlock\|reset` | lock, unlock (drag) or reset the Audit tiles |
| `/bwk audit scan\|dump\|status` | scan now, list your auras with spell IDs, show what's checked |

## Alerts

Tells your group when a taunt or threat ability fails (missed, dodged, parried, resisted, immune...), when you're
stunned, feared, incapacitated or disarmed, and whispers players whose threat gets close to yours.

- **General:** quiet while threat is solid (non-taunt failures aren't announced while you're well ahead on
  threat; taunts always are), test buttons.
- **Abilities:** which of your class's abilities are tracked (Warrior, Paladin, Druid, Shaman).
- **CC & Disarm:** what to announce and the time between alerts.
- **Threat whispers:** on/off, only while tanking, threshold, time between whispers.
- **Channel:** Auto (Raid Warning when you lead or assist a raid, else Raid or Party), Say, Party, Raid,
  Raid Warning. Solo, alerts are shown only to you.

## Audit

Pre-pull tiles for Warrior and Paladin tanks. A tile shows only when something needs attention: no tiles means
all good. Each tile shows the live buff and timer even in combat.

- **Self buffs and stance:** Battle Shout and Defensive Stance, or Righteous Fury. Click to cast. In combat a
  sound plays (and the tile glows) about 15 s before your own buff fades.
- **Group buffs and blessings:** from the classes in your group; click to ask in party/raid chat. When the buff
  arrives, the caster gets a thank-you whisper.
- **Consumables:** Well Fed and the weapon buff, optionally an elixir or a flask; click to open your bags.
- **Healthstone:** when a warlock is in the group and you carry none.
- **Debuffs:** one tile per debuff type you or your group can remove; click to dispel yourself or ask.
- **Blessing of Salvation:** right-click to cancel it, in combat too.

Pages: Checks, Blessings (priority per tank class), Tiles (lock, size, position), Sound, Tools. While the window
shows the Audit tab, every tile is shown as a preview.

## Settings

- **Areas:** turn Alerts, Audit and Marking on or off (also with the switch at the top of each tab).
  Not available in combat.
- **Window:** window size (60-140 %), reset size and position, show or hide the minimap button.
- **Debug:** debug trace, Lua error popups and taint log, recorded errors, last blocked action.

Settings are saved account-wide (`BulwarkDB`); the last tab and page are saved per character (`BulwarkCharDB`).
