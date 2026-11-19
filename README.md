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
| `/bwk mark abilities [name]` | what a dungeon mob casts and when (your target, or by name) |
| `/bwk mark brief [preview\|status\|test]` | post the interrupt briefing for the pack in view; `preview` prints it only, `status` says why the tile is hidden, `test` shows the tile solo |
| `/bwk utilities avoid` | print your attack table (same as the Avoidance page) |
| `/bwk utilities tracker [reset]` | show or hide the enchant mats tracker; `reset` moves it back under the minimap |

## Alerts

Tells your group when a taunt or threat ability fails (missed, dodged, parried, resisted, immune...), when you're
stunned, feared, incapacitated or disarmed, and whispers players whose threat gets close to yours.

- **General:** quiet while threat is solid (non-taunt failures aren't announced while you're well ahead on
  threat; taunts always are), test buttons.
- **Abilities:** which of your class's abilities are tracked (Warrior, Paladin, Druid). Only abilities that
  exist on Forever. Paladin: Judgement counts as a taunt while Seal of Fury is up (that's when it taunts), otherwise
  as a threat ability; Holy Strike.
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
- **Debuffs:** one tile per debuff type you or your group can remove; click to dispel yourself or ask. They sit in
  their own row: keep it near your character and the buff tiles somewhere else, each with its own size.
- **Gear:** defense skill not maxed (in a group), tanking without a shield, low durability.
- **Resting:** in a city or an inn, buff and consumable tiles stay hidden; gear warnings and debuffs still show
  (Audit > Tiles > Hide while resting, on by default).

Pages: Checks, Blessings (priority per tank class), Tiles (lock, sizes, positions, hide while resting), Sound, Tools. While the window
shows the Audit tab, every tile is shown as a preview. Both rows can also be moved in Blizzard's HUD Edit Mode.

## Marking

Plans raid marks for the pack in front of you and puts them on with one key. The game doesn't let addons mark by
themselves, so marking always happens on a key press (bind the keys under Keybindings > AddOns > Bulwark):

- **Mark planned pack:** marks the planned pack (faint icons above the nameplates show the plan).
- **Next skull on target** and **next free icon on target:** in-combat overrides on your target.
- **Clear all marks:** follow marks come back on.
- **Post briefing:** posts the briefing for the pack in view (see Briefing below).

- **Team page:** the kill order (top first), each mark's role (Tank, CC or Follow) and player; Announce posts it,
  naming the marked mobs (`Kill order: {skull} Searing Blade Cultist > {cross} Searing Blade Enforcer`). Saved per
  character.
- **Mob names in dungeons:** the game hides mob names and marks from addons inside dungeons. When you target a mob,
  Bulwark sends you a hidden whisper with `%t`; the game fills in the mob's name and mark, so Bulwark learns them.
  You never see these whispers. Tab through a pack before announcing. Not during boss fights (the game blocks it).
  After each fight, the game's damage meter also tells Bulwark which mobs you fought. Marks other players put on
  are learned the same way: the announcement names those mobs too, `/bwk mark plan` shows who wears an icon, and an
  icon on a mob Bulwark saw die is reused even when its corpse is out of range.
- **Mobs page:** what Bulwark learned per zone (priority, type, fixed icon, CC class), page by page. In dungeons,
  each mob gets its own entry under its real name once Bulwark learns it, starting with the settings of the body
  entry it matched ("Searing Blade Cultist +2"); existing entries are never changed, and body entries stay as the
  fallback for mobs not learned yet.
- **Briefing page:** per dungeon, every mob's casts with Bulwark's default priority; set your own (must, should,
  info, ignore) and a note for the group. Saved by mob name, for every dungeon. A green check marks casts seen in
  play; grey text in a note box is a curated hint. See Briefing below.
- **Options:** planned icons above nameplates, Shift-hover to select a pack, only nearby mobs in view, record new
  mob types in dungeons, learn mob names and marks in dungeons.
- **Keys:** the current bindings, and macros that still use TankMarkForever's button names.
- **HUD:** a small always-on list of the marks; click a mark to switch it off for the next pulls, right-click to
  open the Team page, click the title to collapse it.

### Briefing

Before a pull, tell the group who interrupts what. Out of combat, in a dungeon and in a group, a tile appears when
the pack in view (or a boss you target) has casts worth stopping; click it or press **Post briefing**:

```
[Bulwark] Interrupt: {skull} Ragefire Shaman: Healing Wave -> Tankard (Shield Bash); Ragefire Shaman: Healing Wave -> Kira (Earth Shock)
[Bulwark] Best effort: Lightning Bolt, Shadow Bolt
[Bulwark] Can't interrupt: Frightening Howl (Terrorhowl)
[Bulwark] Note: Curse of Weakness (Jergosh the Invoker): Curse on the tank: remove it.
```

- **What matters:** heals and crowd control with a cast time are *must*; other casts of 2 seconds or more are *should*
  (best effort); curated hints and your own choices on the Briefing page change that.
- **Who interrupts:** you (the tank) take the most important cast; then one player per caster, fastest interrupt
  first (Earth Shock, Kick, Pummel, Shield Bash, Counterspell), stuns (Hammer of Justice, Bash) only when nobody else
  is free. Other players' interrupts come from their class and level; yours from your spellbook and shield.
- **Casts kicks can't stop** (the game's own spell data says so): a heal or crowd control goes to a stun if someone
  has one, otherwise it's listed under *Can't interrupt* so the group knows it's coming; other such casts are left out.
- **Mobs** are named by Marking (Tab through the pack first); unnamed mobs are never guessed. Marks show as icons.
- **Learns in play:** after each fight the game's damage meter tells Bulwark which enemy spells hit your group and
  which ones you interrupted; new ones join that mob's casts (Forever-only dungeons fill up this way).
- The tile hides in combat and boss encounters (the game blocks addon chat there anyway), and after posting until
  the pack changes. Move it in Edit Mode; switch it off on the Briefing page.

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
  Paladins also see spell power enchants (their threat stat: Mystic armor kits, Necklace - Spell Power, Weapon -
  Revelation...), with the spell power in the tooltip; other classes don't.
  Tick enchants to put them on the Enchant list. Item-level and level requirements are respected (armor kits need
  item level 15-45, Zul'Gurub idols level 60).
- **Enchant list:** the enchants you ticked and the mats they still need, have/need counted over bags and bank.
  An enchant drops off once it's on the item. **Track on screen** shows the mats in a quest-tracker style list
  that greys each line out once you have enough (drag its title to move it, shift-click a line to link the item).
  **With [Auctionator](https://www.curseforge.com/wow/addons/auctionator) installed** (optional, never required): what
  the missing mats cost (the cheaper of the last auction house scan and a vendor that sells them), each enchant's cost in
  its tooltip, and **Send to Auctionator**, which puts the missing amounts into the shopping list "Bulwark Enchants".
- **Options:** an item tooltip line showing how an item changes your total avoidance, and a mob tooltip line when
  a mob can crush you. Both off by default.

## Settings

- **Areas:** turn Alerts, Audit, Marking and Utilities on or off (also with the switch at the top of each tab).
  Not available in combat.
- **Window:** window size (60-140 %), reset size and position, show or hide the minimap button.
- **Debug:** debug trace, Lua error popups and taint log, recorded errors, last blocked action.

Settings are saved account-wide (`BulwarkDB`); the last tab and page, Marking's team, and the Gear page's set
purposes, enchant list and tracker position are saved per character (`BulwarkCharDB`).

## Credits

Mob ability data (`Areas/Marking/Data/MobAbilities.lua`):

- Classic dungeons and raids: the [cMaNGOS classic-db](https://github.com/cmangos/classic-db) world database (GPL-3.0), checked
  against the game's own spell data; for bosses scripted in code, the spells their
  [cMaNGOS mangos-classic](https://github.com/cmangos/mangos-classic) boss scripts use (GPL-2).
- Forever-only dungeons: what each mob cast, and which casts players interrupted, in public
  [Warcraft Logs](https://www.warcraftlogs.com) reports of completed runs (a few per dungeon), read through the Warcraft
  Logs API. Only mob and spell data is kept. Entries are marked `wcl = true`, spells from it trigger `wcl`.
- Briefing hints (`MK.BriefingHints`, from `tools/data/briefing-hints.json` in the development workspace): ability
  flags of the Ruins of Lordaeron and Hall of Thanes bosses adapted from
  ForeverDungeonTools 1.0.1 by Samy Khayat (a modified
  MythicDungeonTools by Nnoggie, GPL-2.0); facts only, notes in our own words. Ragefire Chasm boss hints are Bulwark's own.

## License

Copyright (C) 2026 Azuriel-stream

Bulwark is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.
