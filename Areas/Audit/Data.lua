local ADDON_NAME, NS = ...

-- Spell/item IDs for WoW: Forever 1.60.1, collected from Wowhead's Forever database (workspace tools/wowhead.ps1; from TankAuditForever Data/Buffs.lua).
-- Auras carry the ID of the rank that was cast, so every rank is listed. Verify with /bwk audit dump.
-- Display names come from the client (C_Spell.GetSpellName) unless an entry sets `label` (a locale key).

NS.AuditData = {}
local D = NS.AuditData

-- Self buffs per tank class. `stance` = shapeshift spellID that must be active (an OOC prompt, not an aura tile).
-- `requireKnown` = only check when the player knows the spell. `skipSolo` = ignore when ungrouped.
-- `warn` = seconds before expiry at which the tile's countdown turns red.
-- `alert` = in-combat sound + glow, timed from your own last cast (own casts aren't secret);
-- `duration` = fallback until the real duration is learned out of combat.
-- `strength` = [spellID] = base value per rank, for buffs other players can put on you too (user 2026-11-14): someone
-- else's copy counts only when it's at least as strong as yours (Scanner.CompareSelfBuff); a weaker one = missing.
D.SELF = {
    WARRIOR = {
        { key = "BATTLE_SHOUT", ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 27578, 25101 }, warn = 15,
          requireKnown = true, alert = true, duration = 180, icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
          -- attack power per rank, wowf 1.60.1.70938 [data]; 27578 is an old 120 s version (not a player rank);
          -- 25101 = a non-player "Battle Shout", 200 AP for 15 min [data], seen on the user 2026-11-19 (it showed as
          -- missing while it wasn't listed). NPC 20/30 s versions (24438, 26043) left out: too short to matter.
          strength = { [6673] = 9, [5242] = 21, [6192] = 33, [11549] = 51, [11550] = 78, [11551] = 111,
                       [25289] = 139, [27578] = 185, [25101] = 200 } },
        { key = "DEFENSIVE_STANCE", stance = 71, skipSolo = true, icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    },
    PALADIN = {
        { key = "RIGHTEOUS_FURY", ids = { 25780 }, warn = 60, requireKnown = true, alert = true, duration = 1800,
          icon = "Interface\\Icons\\Spell_Holy_SealOfFury" },
    },
}

-- Group buffs from other classes. Checked only when a `provider` class is in the group
-- (`subgroupOnly`: in your raid subgroup). `skipFor` = tank classes that don't need it.
-- `greater` = group/greater versions that also satisfy the buff.
D.GROUP = {
    { key = "FORTITUDE", provider = "PRIEST", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938 }, greater = { 21562, 21564 } },
    { key = "SPIRIT", provider = "PRIEST", icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", skipFor = { WARRIOR = true }, -- mana regen only
      ids = { 14752, 14818, 14819, 27841 }, greater = { 27681 } },
    { key = "MARK_OF_THE_WILD", provider = "DRUID", icon = "Interface\\Icons\\Spell_Nature_Regeneration",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 1291335, 1310503 }, greater = { 21849, 21850 } },
    { key = "THORNS", provider = "DRUID", icon = "Interface\\Icons\\Spell_Nature_Thorns",
      ids = { 467, 782, 1075, 8914, 9756, 9910 } },
    { key = "ARCANE_INTELLECT", provider = "MAGE", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", skipFor = { WARRIOR = true },
      ids = { 1459, 1460, 1461, 10156, 10157 }, greater = { 23028 } },
    { key = "BATTLE_SHOUT", provider = "WARRIOR", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", subgroupOnly = true, skipFor = { WARRIOR = true },
      ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 27578, 25101 } },
    { key = "PALADIN_AURA", provider = "PALADIN", icon = "Interface\\Icons\\Spell_Holy_DevotionAura", subgroupOnly = true, label = "PALADIN_AURA",
      castId = 465, -- Devotion Aura: what a paladin tank casts when no aura is up
      ids = { 465, 643, 1032, 10290, 10291, 10292, 10293,   -- Devotion
              7294, 10298, 10299, 10300, 10301,             -- Retribution
              19746,                                        -- Concentration
              19876, 19895, 19896,                          -- Shadow Resistance
              19888, 19897, 19898,                          -- Frost Resistance
              19891, 19899, 19900 } },                      -- Fire Resistance
}

-- Paladin blessings, ordered by the user's priority list (NS.DefaultConfig.audit.blessingPriority).
-- Blessing of Sanctuary isn't in Forever (Wowhead); Kings is baseline (not a talent) on Forever.
D.BLESSINGS = {
    KINGS  = { icon = "Interface\\Icons\\Spell_Magic_MageArmor", ids = { 20217 }, greater = { 25898 } },
    MIGHT  = { icon = "Interface\\Icons\\Spell_Holy_FistOfJustice", ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, greater = { 25782, 25916 } },
    LIGHT  = { icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", ids = { 19977, 19978, 19979 }, greater = { 25890 } },
    WISDOM = { icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom", ids = { 19742, 19850, 19852, 19853, 19854, 25290 }, greater = { 25894, 25918 } },
}

-- Fixed tile order for blessing tiles (which ones show comes from the user's priority list)
D.BLESSING_ORDER = { "KINGS", "MIGHT", "LIGHT", "WISDOM" }

-- Consumables (in groups and/or solo: audit.consumablesInGroup / consumablesSolo)
D.WELL_FED = { 19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941,
               1225778, 1225779, 1225780, 1225782, 1248406, 1248420, 1248421, 1248422, 1248688,
               1249519, 1249520, 1249521, 1249523, 1249907, 1249926, 1249927, 1283082, 1294007,
               1302064, 1319310,
               25661 }  -- Dirge's Kickin' Chimaerok Chops: "Increased Stamina", not named Well Fed [data]
-- Elixir / flask BUFF spell IDs (not item IDs), generated 2026-10-05 from Wowhead Forever's elixir and flask item
-- categories: each item's Use: spell. Utility draughts (water breathing, detection, Giant Growth, Noggenfogger) and
-- plain alcohol are excluded. Forever renamed some buffs after their item (673 = Elixir of Minor Defense) [in-game].
D.ELIXIRS = {
    2367, -- Elixir of Minor Strength
    2374, -- Elixir of Minor Agility
    2378, -- Elixir of Minor Fortitude
    3219, -- Minor Troll's Blood Elixir
    3166, -- Elixir of Wisdom
    3222, -- Lesser Troll's Blood Elixir
    3220, -- Elixir of Lesser Defense
    3160, -- Elixir of Lesser Agility
    3164, -- Elixir of Ogre Strength
    3593, -- Elixir of Lesser Fortitude
    3223, -- Troll's Blood Elixir
    673, -- Elixir of Minor Defense
    7844, -- Elixir of Fire Power
    10667, -- R.O.I.D.S.
    10668, -- Lung Juice Cocktail
    10669, -- Ground Scorpok Assay
    10692, -- Cerebral Cortex Compound
    10693, -- Gizzard Gum
    11328, -- Elixir of Agility
    11349, -- Elixir of Defense
    11371, -- Gift of Arthas
    11390, -- Arcane Elixir
    11396, -- Elixir of Greater Intellect
    11334, -- Elixir of Greater Agility
    11405, -- Elixir of Greater Strength
    11406, -- Potion of Demon Slaying
    11474, -- Elixir of Shadow Power
    17038, -- Winterfall Firewater
    11348, -- Elixir of Greater Defense
    17535, -- Elixir of the Sages
    17538, -- Elixir of the Mongoose
    17537, -- Elixir of Brute Force
    17539, -- Greater Arcane Elixir
    21920, -- Elixir of Frost Power
    24361, -- Major Troll's Blood Elixir
    24363, -- Mageblood Elixir
    24382, -- Spirit of Zanza
    24417, -- Sheen of Zanza
    24383, -- Swiftness of Zanza
    1310077, -- Elixir of Holy Power
    439959, -- Lesser Arcane Elixir
    1245244, -- Minor Arcane Elixir
    1245249, -- Elixir of Minor Force
    1250889, -- Draught of Predatory Senses
    1250918, -- Elixir of Cunning
    1250920, -- Elixir of the Phalanx
    1250922, -- Minor Cleric's Elixir
    1250924, -- Lesser Cleric's Elixir
    1250925, -- Cleric's Elixir
    1250926, -- Greater Cleric's Elixir
    1250928, -- Elixir of Fortitude
    1250931, -- Elixir of Greater Fortitude
    1250932, -- Elixir of Wicked Regeneration
    1250940, -- Elixir of the Owl
    1250941, -- Elixir of Sages
    1250942, -- Minor Mageblood Elixir
    1250944, -- Lesser Mageblood Elixir
    1250948, -- Greater Mageblood Elixir
    1250971, -- Lesser Arcane Elixir
    1250972, -- Elixir of Nature Power
    1250974, -- Elixir of Minor Spirit
    1250976, -- Elixir of Lesser Spirit
    1250978, -- Elixir of Spirit
    1250979, -- Elixir of Greater Spirit
    1250981, -- Elixir of the Whale
    1250984, -- Elixir of Strength
    1250985, -- Elixir of Ferocity
    1250986, -- Elixir of the Grizzly
    1250988, -- Elixir of Lesser Intellect
    1250989, -- Elixir of Intellect
}
D.FLASKS = {
    17626, -- Flask of the Titans
    17627, -- Flask of Distilled Wisdom
    17628, -- Flask of Supreme Power
    17629, -- Flask of Chromatic Resistance
    1293740, -- Flask of Natural Accuracy
    1293741, -- Flask of Natural Aggression
    1293742, -- Flask of Natural Precision
    1293743, -- Flask of Natural Swiftness
}

-- Scrolls (user 2026-11-22): a tile when a scroll in your bags would give a buff nobody in the group puts on you.
-- Click = use your best usable rank on yourself. `group` = the D.GROUP buff it stands in for: offered only when no
-- provider class is in the group and that buff isn't on you (the stronger of the two replaces the weaker [in-game
-- 2026-11-22, Fortitude vs Scroll of Stamina]). No `group` = no class buff gives it: always offered.
-- Shaman totems (Strength of Earth, Grace of Air) stack with the scrolls [in-game 2026-11-22], so they don't hide a tile.
-- `ranks` best first: item ID -> the buff spell it casts [data: ItemXItemEffect + ItemEffect + SpellEffect,
-- wowf 1.60.1.71037] and its value.
D.SCROLLS = {
    { key = "STAMINA", group = "FORTITUDE", ranks = {
        { item = 10307, spell = 12178, value = 16 }, { item = 4422, spell = 8101, value = 12 },
        { item = 1711, spell = 8100, value = 8 }, { item = 1180, spell = 8099, value = 4 } } },
    { key = "PROTECTION", ranks = {   -- armor; the buff is named "Armor", like Elixir of Defense: IDs only
        { item = 10305, spell = 12175, value = 240 }, { item = 4421, spell = 8095, value = 180 },
        { item = 1478, spell = 8094, value = 120 }, { item = 3013, spell = 8091, value = 60 } } },
    { key = "STRENGTH", ranks = {
        { item = 10310, spell = 12179, value = 17 }, { item = 4426, spell = 8120, value = 13 },
        { item = 2289, spell = 8119, value = 9 }, { item = 954, spell = 8118, value = 5 } } },
    { key = "AGILITY", ranks = {
        { item = 10309, spell = 12174, value = 17 }, { item = 4425, spell = 8117, value = 13 },
        { item = 1477, spell = 8116, value = 9 }, { item = 3012, spell = 8115, value = 5 } } },
    { key = "INTELLECT", group = "ARCANE_INTELLECT", skipFor = { WARRIOR = true }, ranks = {
        { item = 10308, spell = 12176, value = 16 }, { item = 4419, spell = 8098, value = 12 },
        { item = 2290, spell = 8097, value = 8 }, { item = 955, spell = 8096, value = 4 } } },
    { key = "SPIRIT", group = "SPIRIT", skipFor = { WARRIOR = true }, ranks = {
        { item = 10306, spell = 12177, value = 15 }, { item = 4424, spell = 8114, value = 11 },
        { item = 1712, spell = 8113, value = 7 }, { item = 1181, spell = 8112, value = 3 } } },
}

D.HEALTHSTONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
                   5510, 19010, 19011, 9421, 19012, 19013 }

-- Fallback icons for category entries
D.ICONS = {
    WELL_FED = "Interface\\Icons\\Spell_Misc_Food",
    WEAPON_BUFF = "Interface\\Icons\\INV_Stone_SharpeningStone_01",
    ELIXIR = "Interface\\Icons\\INV_Potion_32",
    FLASK = "Interface\\Icons\\INV_Potion_62",
    HEALTHSTONE = "Interface\\Icons\\INV_Stone_04",
    SCROLL = "Interface\\Icons\\INV_Scroll_07",
    DEFENSE_SKILL = "Interface\\Icons\\Ability_Defend",
    NO_SHIELD = "Interface\\Icons\\INV_Shield_06",
    DURABILITY = "Interface\\Icons\\Trade_BlackSmithing",
    UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- Which classes can remove each debuff type, and from which level (Wowhead Forever learn levels:
-- Dispel Magic 18, Cleanse 42, Remove Lesser Curse 18, Remove Curse 24, Cure Poison 14 (druid) / 16 (shaman),
-- Purify 8, Cure Disease 14 (priest) / 22 (shaman)).
D.DISPEL_LEVELS = {
    Magic   = { PRIEST = 18, PALADIN = 42 },
    Curse   = { MAGE = 18, DRUID = 24 },
    Poison  = { DRUID = 14, PALADIN = 8, SHAMAN = 16 },
    Disease = { PRIEST = 14, PALADIN = 8, SHAMAN = 22 },
}
D.DISPEL_ORDER = { "Magic", "Curse", "Poison", "Disease" }

-- The player's own dispels per debuff type (first known spell is cast)
D.PLAYER_DISPELS = {
    PALADIN = {
        Magic   = { 4987 },          -- Cleanse
        Poison  = { 4987, 1152 },    -- Cleanse, Purify
        Disease = { 4987, 1152 },
    },
    WARRIOR = {},
}

-- Chat messages (requests, thank-yous) live in Voices.lua.
