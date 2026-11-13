# Bulwark

A tanking suite for **WoW: Forever** (interface 16001): combat alerts, a pre-pull audit, one-key raid marking and
tank utilities (avoidance calculator, enchant check), in one addon with one window.

Bulwark replaces three standalone addons, one tab each (Utilities is new):

| Tab | Replaces |
|---|---|
| Alerts | TankAlertForever |
| Audit | TankAuditForever |
| Marking | TankMarkForever |

Coming from one of them? Disable it in the AddOns list. While it's still loaded, Bulwark keeps that tab's area
switched off, so nothing runs twice. Settings start fresh in Bulwark. Keys you bound to TankMarkForever's marking
buttons move over by themselves; macros that `/click TMF_...` need `TMF_` changed to `BWK_` (Marking > Keys lists them).

## Opening Bulwark

- `/bwk` (or `/bulwark`) opens and closes the window. Esc closes it too.
- The minimap button: left-click opens or closes the window, right-click opens Settings, drag to move it.

## Commands

| Command | What it does |
|---|---|
| `/bwk` | open or close the window |
| `/bwk alerts`, `/bwk audit`, `/bwk mark`, `/bwk utilities` | open that tab |
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
| `/bwk audit scan\|dump\|status\|voice` | scan now, list your auras with spell IDs, show what's checked, preview your chat messages |
| `/bwk mark announce\|plan\|status` | post the kill order, print the pack plan, show status |
| `/bwk mark learn <1-9\|ignore\|cc> [icon\|class]`, `/bwk mark forget` | teach or forget the hovered/targeted mob |
| `/bwk mark select clear`, `/bwk mark overlay` | clear the Shift-hover selection, toggle planned icons |
| `/bwk utilities avoid` | print your attack table (same as the Avoidance page) |
| `/bwk utilities tracker [reset]` | show or hide the enchant mats tracker; `reset` moves it back under the minimap |

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
  arrives, the caster gets a thank-you whisper. Requests name the one player who can answer (or the class, plural,
  when several can) and speak in your race's voice: each of Forever's races, High Order and Windshaper Skyborne
  included, has its own lines (Audit > Checks > Messages; off = plain lines).
- **Consumables:** Well Fed and the weapon buff, optionally an elixir or a flask; click to open your bags.
- **Healthstone:** when a warlock is in the group and you carry none.
- **Debuffs:** one tile per debuff type you or your group can remove; click to dispel yourself or ask.
- **Blessing of Salvation:** right-click to cancel it, in combat too.
- **Gear:** defense skill not maxed (in a group), tanking without a shield, low durability.

Pages: Checks, Blessings (priority per tank class), Tiles (lock, size, position), Sound, Tools. While the window
shows the Audit tab, every tile is shown as a preview.

## Marking

Plans raid marks for the pack in front of you and puts them on with one key. The game doesn't let addons mark by
themselves, so marking always happens on a key press (bind the keys under Keybindings > AddOns > Bulwark):

- **Mark planned pack:** marks the planned pack (faint icons above the nameplates show the plan).
- **Next skull on target** and **next free icon on target:** in-combat overrides on your target.
- **Clear all marks:** follow marks come back on.

- **Team page:** the kill order (top first), each mark's role (Tank, CC or Follow) and player; Announce posts it.
  Saved per character.
- **Mobs page:** what Bulwark learned per zone (priority, type, fixed icon, CC class), page by page.
- **Options:** planned icons above nameplates, Shift-hover to select a pack, only nearby mobs in view, record new
  mob types in dungeons.
- **Keys:** the current bindings, and macros that still use TankMarkForever's button names.
- **HUD:** a small always-on list of the marks; click a mark to switch it off for the next pulls, right-click to
  open the Team page, click the title to collapse it.

Moving over from TankMarkForever: keys bound to its buttons move to Bulwark's buttons automatically. Macros that
`/click TMF_...` buttons need `TMF_` changed to `BWK_` by hand (Bulwark lists them).

## Utilities

Tank helpers for Warrior and Paladin tanks that read your character (out of combat: in combat the game hides
these values, so the pages keep the last ones).

- **Avoidance:** your attack table against a mob 0-3 levels above you (+3 = raid boss): miss, dodge, parry, block,
  crit, crushing blows and hits; whether you're uncrushable and crit immune, and how much defense you still need.
  Tick Shield Block or Holy Shield to count it.
- **What if:** sliders for defense, agility, dodge, parry and block show how the table would change.
- **Buffs:** what missing buffs and consumables (Kings, Mark of the Wild, Mongoose, Greater Agility, Grace of Air)
  would add.
- **Stat values:** how much total avoidance one point of each stat gives you, and how many points make 1 %.
- **Gear:** an enchant check for each gear set saved in the game's Equipment Manager (or what you wear, when it
  matches no saved set). Red slot: no enchant. Yellow slot: another enchant adds more total avoidance.
  **Suggestions are ranked by avoidance gain, not Best-in-Slot**; stamina is shown second. For a Warrior with
  Shield Block and a shield, block chance doesn't count: used on cooldown, Shield Block already blocks almost every
  swing that isn't dodged or parried. Give each set a purpose:
  Avoidance (missing and weaker enchants), Threat (missing only; use it for high-stamina sets too), Resistance
  (missing only, resistance enchants count as correct) or Don't check. Hover a slot for the reason;
  right-click marks a slot as intentional for that set; left-click lists the enchants that fit, with their mats.
  Tick enchants to put them on the Enchant list. Item-level and level requirements are respected (armor kits need
  item level 15-45, Zul'Gurub idols level 60).
- **Enchant list:** the enchants you ticked and the mats they still need, have/need counted over bags and bank.
  An enchant drops off once it's on the item. **Track on screen** shows the mats in a quest-tracker style list
  that greys each line out once you have enough (drag its title to move it, shift-click a line to link the item).
- **Options:** an item tooltip line showing how an item changes your total avoidance, and a mob tooltip line when
  a mob can crush you. Both off by default.

## Settings

- **Areas:** turn Alerts, Audit, Marking and Utilities on or off (also with the switch at the top of each tab).
  Not available in combat.
- **Window:** window size (60-140 %), reset size and position, show or hide the minimap button.
- **Debug:** debug trace, Lua error popups and taint log, recorded errors, last blocked action.

Settings are saved account-wide (`BulwarkDB`); the last tab and page, Marking's team, and the Gear page's set
purposes, enchant list and tracker position are saved per character (`BulwarkCharDB`).
